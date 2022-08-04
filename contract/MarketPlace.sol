// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.6;

pragma experimental ABIEncoderV2;

import  "./lib/Initializable.sol";
import  "./MyceNFT.sol";
import  "./lib/IERC20.sol";
import  "./lib/SafeERC20.sol";
import  "./lib/ReentrancyGuard.sol";
import  "./lib/IERC165.sol";
import  "./lib/DataTypes.sol";
import  "./lib/Errors.sol";
import  "./lib/OwnerPausableUpgradeSafe.sol";
import  "./lib/IERC721TokenAuthor.sol";


/**
 * @dev Auction between NFT holders and participants.
 */
contract MarketPlace is OwnerPausableUpgradeSafe, ReentrancyGuard, Initializable {
    using SafeERC20 for IERC20;

    mapping(uint256 /*tokenId*/ => DataTypes.AuctionData) internal _nftId2auction;
    uint256 public minPriceStepNumerator;
    uint256 constant public DENOMINATOR = 10000;
    uint256 constant public MIN_MIN_PRICE_STEP_NUMERATOR = 1;  // 0.01%
    uint256 constant public MAX_MIN_PRICE_STEP_NUMERATOR = 10000;  // 100%

//    uint256 public authorRoyaltyNumerator;
    uint256 public overtimeWindow;
 
    uint256 constant MAX_OVERTIME_WINDOW = 365 days;
    uint256 constant MIN_OVERTIME_WINDOW = 1 minutes;



    // IERC20[] public payableTokens;
    // IERC20 public payableToken;
    MyceNFT public nft;


    //treasury address
    address public treasury;
    //Platform rate
    uint256 public feeNumerator;

  
    event TreasurySet(
        address indexed treasury
    );

    event AuctionCreated(
        uint256 indexed nftId,
        address indexed auctioneer,
        uint8 auctionType,
        uint256 startPrice,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 reservePrice,
        address priceToken
    );

   
    event RoyaltyPaid(
        uint256 indexed nftId,
        address indexed author,
        uint256 amount,
        address amountToken
    );

    event FeePaid(
        uint256 indexed nftId,
        address indexed payer,
        uint256 feeAmount,
        address amountToken
    );

  
    event AuctionCanceled(
        uint256 indexed nftId,
        address indexed canceler
    );

   
    event MinPriceStepNumeratorSet(
        uint256 minPriceStepNumerator
    );

 

    /**
     * @notice Emitted when a new auction params are set.
     *
     * @param overtimeWindow.
     */
    event OvertimeWindowSet(
        uint256 overtimeWindow
    );

  
    event BidSubmitted(
        uint256 indexed nftId,
        address indexed bidder,
        uint256 amount,
        address amountToken,
        uint256 endTimestamp
    );

   
    event WonNftClaimed(
        uint256 indexed nftId,
        address indexed winner,
        address claimCaller,
        uint256 wonBidAmount,
        uint256 paidToAuctioneer,
        uint256 fee
    );

    event BidNftClaimed(
          uint256 indexed nftId,
        address indexed winner,
        address claimCaller,
        uint256 wonBidAmount,
        uint256 paidToAuctioneer,
        uint256 timestamp,
        uint256 fee
    );

  

    function canCancel(uint256 tokenId) internal view returns(bool) {
        DataTypes.AuctionData memory auction = _nftId2auction[tokenId];
        require(
            auction.auctioneer != address(0),
            Errors.AUCTION_NOT_EXISTS
        );

        require(
            msg.sender == auction.auctioneer || msg.sender == owner() || msg.sender == auction.currentBidder,
            Errors.NO_RIGHTS
        );

        if(block.timestamp < auction.startTimestamp){
            return true;
        }

        if(auction.currentBidder == address(0) ){
            return true;
        }

        if(auction.endTimestamp < block.timestamp && auction.reservePrice>auction.currentBid){
            return true;
        }

       return false;
    }

    function getPaused() external view returns(bool) {
        return _paused;
    }

    
    function initialize(
        uint256 _overtimeWindow,
        address _nft,
        address _ownerAddress,
        address _treasury,
        uint256 _feeNumerator,
        uint256 _minPriceStepNumerator
    ) external initializer {
        require(
            _ownerAddress != address(0),
            Errors.ZERO_ADDRESS
        );
        require(
            _nft != address(0),
            Errors.ZERO_ADDRESS
        );
        require(
            _treasury != address(0),
            Errors.ZERO_ADDRESS
        );
        _transferOwnership(_ownerAddress);
        nft = MyceNFT(_nft);
        treasury = _treasury;
        setOvertimeWindow(_overtimeWindow);
        setFeeNumerator(_feeNumerator);
        setMinPriceStepNumerator(_minPriceStepNumerator);
    }

 
    function setTreasury(address treasuryAddress) external onlyOwner {
        require(
            treasuryAddress != address(0),
            Errors.ZERO_ADDRESS
        );
        treasury = treasuryAddress;
        emit TreasurySet(treasuryAddress);
    }

   
 

   
    function setOvertimeWindow(uint256 newOvertimeWindow) public onlyOwner {
        require(newOvertimeWindow >= MIN_OVERTIME_WINDOW && newOvertimeWindow <= MAX_OVERTIME_WINDOW,
            Errors.INVALID_AUCTION_PARAMS);
        overtimeWindow = newOvertimeWindow;
        emit OvertimeWindowSet(newOvertimeWindow);
    }


    function setMinPriceStepNumerator(uint256 newMinPriceStepNumerator) public onlyOwner {
        require(newMinPriceStepNumerator >= MIN_MIN_PRICE_STEP_NUMERATOR &&
            newMinPriceStepNumerator <= MAX_MIN_PRICE_STEP_NUMERATOR,
            Errors.INVALID_AUCTION_PARAMS);
        minPriceStepNumerator = newMinPriceStepNumerator;
        emit MinPriceStepNumeratorSet(newMinPriceStepNumerator);
    }



  
    function setFeeNumerator(uint256 newFeeNumerator) public onlyOwner {
        require(newFeeNumerator <= DENOMINATOR, Errors.INVALID_AUCTION_PARAMS);
        feeNumerator = newFeeNumerator;
    }



  

 
  
    function createAuction(
        uint256 nftId,
        uint8 auctionType,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 startPrice,
        uint256 reservePrice,
        address specificBuyer
    ) external nonReentrant whenNotPaused {
        require(_nftId2auction[nftId].auctioneer == address(0), Errors.AUCTION_EXISTS);
        require(startPrice > 0, Errors.INVALID_AUCTION_PARAMS);
        require(auctionType ==1 || auctionType == 2,"error auction type");
        (address author,uint256 authorFee,IERC20 authorToken,address authorFeeAddress) = nft.getTokenInfo(nftId);
        DataTypes.AuctionData memory auctionData = DataTypes.AuctionData(
            startPrice,
            address(authorToken),
            msg.sender,
            address(0),  // bidder
            startTimestamp,
            endTimestamp,  // endTimestamp
            reservePrice,
            specificBuyer,
            authorFee,
            authorFeeAddress,
            author,
            auctionType
        );
        _nftId2auction[nftId] = auctionData;
        nft.transferFrom(msg.sender, address(this), nftId);  // maybe use safeTransferFrom
        emit AuctionCreated(nftId, msg.sender,auctionType, startPrice,startTimestamp,endTimestamp,reservePrice, auctionData.bidToken);
    }

   
    function claimWonNFT(uint256 nftId) external nonReentrant whenNotPaused {
        DataTypes.AuctionData memory auction = _nftId2auction[nftId];

        address auctioneer = auction.auctioneer;
        address winner = auction.currentBidder;
        uint256 endTimestamp = auction.endTimestamp;
        uint256 currentBid = auction.currentBid;
        uint256 payToAuctioneer = currentBid;
        IERC20 payableToken = IERC20(auction.bidToken);

        address author = auction.author;
        uint256 authorFee = auction.authorFee;
        address authorFeeAddress = auction.authorFeeAddress;

        require(block.timestamp > endTimestamp, Errors.AUCTION_NOT_FINISHED);
        require(winner != address(0), Errors.EMPTY_WINNER);  // auction does not exist or did not start, no bid
        require(currentBid >= auction.reservePrice,Errors.LOWER_THAN_RESERVE_PRICE);
        require((msg.sender == auctioneer) || (msg.sender == winner) || (msg.sender == owner()), Errors.NO_RIGHTS);
        delete _nftId2auction[nftId];  // storage change before external calls

        // warning: will not work for usual erc721
        // address author = IERC721TokenAuthor(address(nft)).tokenAuthor(nftId);
        //版权税
        if (author != auctioneer) {  // pay royalty
            uint256 payToAuthor = currentBid * authorFee / DENOMINATOR;
            payToAuctioneer -= payToAuthor;
            emit RoyaltyPaid(nftId, author, payToAuthor, auction.bidToken);
            // erc20
            payableToken.safeTransfer(authorFeeAddress, payToAuthor);
        }


        //平台手续费
        uint256 fee = 0;
        fee = currentBid * uint256(feeNumerator) / uint256(DENOMINATOR);

        if (fee > 0) {
            payToAuctioneer -= fee;
            payableToken.safeTransfer(treasury, fee);
        }


        emit FeePaid({
        nftId: nftId,
        payer: winner,
        feeAmount: fee,
        amountToken: address(payableToken)
        });
        emit WonNftClaimed(nftId, winner, msg.sender, currentBid, payToAuctioneer,fee);
        payableToken.safeTransfer(auctioneer, payToAuctioneer);
        
        // sine we use the only one nft, we don't need to call safeTransferFrom
        IERC721(nft).transferFrom(address(this), winner, nftId);
    }

     function getAuthorFee(uint256 nftId) external view returns(uint256,address) {
        DataTypes.AuctionData memory auction = _nftId2auction[nftId];

       
    
       
        uint256 currentBid = auction.currentBid;
        uint256 payToAuctioneer = currentBid;
        

       
        uint256 authorFee = auction.authorFee;

     
      
        uint256 payToAuthor = currentBid * authorFee / DENOMINATOR;
        payToAuctioneer -= payToAuthor;
    
    
        return (payToAuctioneer,auction.authorFeeAddress);
       
    }

   
    function getAuctionData(uint256 nftId) external view returns (DataTypes.AuctionData memory) {
        DataTypes.AuctionData memory auction = _nftId2auction[nftId];
        require(auction.auctioneer != address(0), Errors.AUCTION_NOT_EXISTS);
        return auction;
    }

    /**
     * @notice Cancel an auction. Can be called by the auctioneer or by the owner.
     *
     * @param nftId The NFT ID of the token to cancel.
     */
    function cancelAuction(
        uint256 nftId
    ) external whenNotPaused nonReentrant {
        DataTypes.AuctionData memory auction = _nftId2auction[nftId];
        require(canCancel(nftId),Errors.CAN_NOT_CANCEL);
        delete _nftId2auction[nftId];
        emit AuctionCanceled(nftId, msg.sender);
        // maybe use safeTransfer (I don't want unclear onERC721Received stuff)
        IERC721(nft).transferFrom(address(this), auction.auctioneer, nftId);
        if(auction.currentBidder != address(0) ){
            IERC20(auction.bidToken).transfer(auction.currentBidder,auction.currentBid);
        }
    }


   
    function bid(
        uint256 nftId,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        DataTypes.AuctionData memory auction = _nftId2auction[nftId];
        require(auction.auctioneer != address(0), Errors.AUCTION_NOT_EXISTS);
        if(auction.auctionType == 1){
            _bid(nftId, amount);
        }else{
            _bidFixPrice(nftId, amount);
        }
    }



    function _bid(
        uint256 nftId,
        uint256 amount
    ) internal {
        DataTypes.AuctionData storage auction = _nftId2auction[nftId];
        uint256 currentBid = auction.currentBid;
        address currentBidder = auction.currentBidder;
        uint256 endTimestamp = auction.endTimestamp;
        address auctionToken = auction.bidToken;
        IERC20 payableToken = IERC20(auctionToken);
        require(
            block.timestamp < endTimestamp && block.timestamp > auction.startTimestamp,  // or not started
            Errors.AUCTION_FINISHED
        );

        uint256 newEndTimestamp = auction.endTimestamp;
//        require(amount > currentBid, Errors.SMALL_BID_AMOUNT);
        require(amount >= (DENOMINATOR + minPriceStepNumerator) * currentBid / DENOMINATOR,
            Errors.SMALL_BID_AMOUNT);


        if (block.timestamp > endTimestamp - overtimeWindow) {
            newEndTimestamp = block.timestamp + overtimeWindow;
            auction.endTimestamp = newEndTimestamp;
        }


        auction.currentBidder = msg.sender;
        auction.currentBid = amount;

        // emit here to avoid reentry events mis-ordering
        emit BidSubmitted(nftId, msg.sender, amount, auction.bidToken, newEndTimestamp);

        if (auctionToken != address(0)){  // erc20
            if (currentBidder != msg.sender) {
                if (currentBidder != address(0)) {
                    payableToken.safeTransfer(currentBidder, currentBid);
                }
                payableToken.safeTransferFrom(msg.sender, address(this), amount);
            } else {
                uint256 more = amount - currentBid;
                payableToken.safeTransferFrom(msg.sender, address(this), more);
            }
        }
    }

  
    function _bidFixPrice(
        uint256 nftId,
        uint256 amount
    ) internal {
        DataTypes.AuctionData memory auction = _nftId2auction[nftId];
        
        address auctioneer = auction.auctioneer;
        uint256 currentBid = auction.currentBid;
        address author = auction.author;
        uint256 endTimestamp = auction.endTimestamp;
        uint256 authorFee = auction.authorFee;
        uint256 payToAuctioneer = amount;
        address auctionToken = auction.bidToken;
        IERC20 payableToken = IERC20(auctionToken);


        require(
            block.timestamp < endTimestamp && (block.timestamp > auction.startTimestamp || auction.specificBuyer == msg.sender),
            Errors.AUCTION_FINISHED
        );

        uint256 newEndTimestamp = block.timestamp;
     

        require(amount >= currentBid, Errors.SMALL_BID_AMOUNT);

        nft.transferFrom(address(this), msg.sender, nftId);
       
        if (author != auctioneer) {  // pay royalty
            uint256 payToAuthor = amount * authorFee / DENOMINATOR;
            payToAuctioneer -= payToAuthor;
            emit RoyaltyPaid(nftId, author, payToAuthor, auction.bidToken);
            // erc20
            payableToken.safeTransferFrom(msg.sender,auction.authorFeeAddress, payToAuthor);
        }

       


        //平台手续费
        uint256 fee = 0;
        fee = amount * uint256(feeNumerator) / uint256(DENOMINATOR);

        if (fee > 0) {
            payToAuctioneer -= fee;
            payableToken.safeTransferFrom(msg.sender,treasury, fee);
        }
      
       emit BidNftClaimed(nftId,  msg.sender, msg.sender, currentBid, payToAuctioneer,newEndTimestamp,fee);

        emit FeePaid({nftId: nftId,payer: msg.sender,feeAmount: fee,amountToken: auctionToken});
        delete _nftId2auction[nftId];

       payableToken.safeTransferFrom(msg.sender,auctioneer, payToAuctioneer);
       
    }

}
