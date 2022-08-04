// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.6;


library DataTypes {
    struct AuctionData {
        uint256 currentBid;
        address bidToken; // determines currentBid token, zero address means ether
        address auctioneer;
        address currentBidder;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 reservePrice;
        address specificBuyer;
        uint256 authorFee;
        address authorFeeAddress;
        address author;
        uint8 auctionType; //1=auction,2=fixPrice

    }
}
