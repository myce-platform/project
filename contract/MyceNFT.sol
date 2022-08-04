// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./lib/Ownable.sol";
import "./lib/ERC721.sol";
import "./lib/IERC20.sol";
import "./lib/ERC721URIStorage.sol";
import "./lib/ERC721Enumerable.sol";
import "./lib/IERC721TokenAuthor.sol";
import "./lib/Errors.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata URI extension.
 */
contract MyceNFT is ERC721, ERC721Enumerable, ERC721URIStorage, IERC721TokenAuthor, Ownable {

    struct TokenInfo {
        address author;
        uint256 authorFee;
        address authorFeeAddress;
        IERC20 authorToken;
    }

    
    uint256 internal _lastTokenId;

    uint256 private constant MAX_AUTHOR_FEE = 1000;

    mapping(uint256 => TokenInfo) private _tokenInfoMapping;

    // mapping(address => bool) private whiteList;

    // string internal _contractURI;

    event ContractURISet(string newContractURI);
    event Mint(address indexed author, address indexed tokenAddress, uint256 indexed tokenId,uint256 authorFee,string tokenIPFSHash,address authorFeeAddress);

    constructor(address ownerAddress) ERC721("MYCE AVATAR NFT", "MYCEAVATAR") Ownable() {
        if (owner() != ownerAddress) {  // openzeppelin v4.1.0 has no _transferOwnership
            require(ownerAddress != address(0), Errors.ZERO_ADDRESS);
            transferOwnership(ownerAddress);
        }
    }

    function _baseURI() override(ERC721) internal pure returns(string memory) {
        return "ipfs://";
    }

    function mintWithTokenURI(string memory _tokenIPFSHash,uint256 _authorFee,IERC20 _authorToken,address _authorFeeAddress) external returns (uint256) {
        require(bytes(_tokenIPFSHash).length > 0, Errors.EMPTY_METADATA);
        require(_authorFee <= MAX_AUTHOR_FEE,Errors.INVALID_FEE_AMOUNT );
        uint256 tokenId = ++_lastTokenId;  // start from 1
        address to = _msgSender();
        _mint(to, tokenId);
        _tokenInfoMapping[tokenId] = TokenInfo(to,_authorFee,_authorFeeAddress,_authorToken);
        _setTokenURI(tokenId, _tokenIPFSHash);
        emit Mint(to,address(_authorToken),tokenId,_authorFee,_tokenIPFSHash,_authorFeeAddress);
        return tokenId;
    }
    

    function burn(uint256 tokenId) external {
        require(ERC721.ownerOf(tokenId) == msg.sender, Errors.NOT_OWNER);
        _burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
    public
    view
    override(ERC721, ERC721URIStorage)
    returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);  // take care about multiple inheritance
        // delete _tokenAuthor[tokenId];
    }

    function tokenAuthor(uint256 tokenId) external override view returns(address) {
        require(_exists(tokenId), Errors.NOT_EXISTS);
        return _tokenInfoMapping[tokenId].author;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        ERC721Enumerable._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return interfaceId == type(IERC721TokenAuthor).interfaceId
        || super.supportsInterface(interfaceId);
    }


    function getTokenInfo(uint256 _tokenId) public view returns(address author,uint256 authorFee,IERC20 authorToken,address authorFeeAddress){
        require(_exists(_tokenId), Errors.NOT_EXISTS);
        TokenInfo memory tokenInfo = _tokenInfoMapping[_tokenId];
        return (tokenInfo.author,tokenInfo.authorFee,tokenInfo.authorToken,tokenInfo.authorFeeAddress);
    }
}
