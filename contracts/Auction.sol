// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "hardhat/console.sol";

contract Auction is IERC721Receiver{

    event NFTReceived(address operator, address from, uint256 tokenId, bytes data);

    address internal _sellerAddress;
    address internal _winnerAddress;
    uint internal _winningPrice;

    address internal _judgeAddress;
    bool internal _judgeDeclared;
    bool internal _nftContractDeclared;
    bool internal _settled;
    bool internal _refunded;

    ERC721 internal _nftContract;
    uint256[] internal _heldTokenIds;

    mapping(address => uint256) internal _pendingWithdrawals;

    // constructor
    constructor(address sellerAddress_) payable {
        _sellerAddress = sellerAddress_;
        if (_sellerAddress == address(0))
          _sellerAddress = msg.sender;

        _judgeAddress = address(0);
        _judgeDeclared = false;
        _nftContractDeclared = false;
        _settled = false;
        _refunded = false;
    }

    // Designate a judge for the auction. This should only be callable
    // by the seller and only callable once. Once the judge is set,
    // nobody can change or revoke the judge.
    function setJudge(address judgeAddress_) public{

        require(msg.sender == _sellerAddress, "Auction: only seller");
        require(!_judgeDeclared, "Auction: judge already set");
        require(judgeAddress_ != address(0), "Auction: invalid judge");

        _judgeAddress = judgeAddress_;
        _judgeDeclared = true;

    }

    // Designate an NFT marketplace used bye the auction. This should only
    // be callable by the seller and only callable once. Once set,
    // nobody can change or marketplace.
    function setNFTContract(ERC721 nftContract_) public{

        require(msg.sender == _sellerAddress, "Auction: only seller");
        require(!_nftContractDeclared, "Auction: NFT contract set");
        require(address(nftContract_) != address(0), "Auction: invalid NFT contract");

        _nftContract = nftContract_;
        _nftContractDeclared = true;

    }

    // This is used in testing.
    // You should use this instead of block.number directly.
    // You should not modify this function.
    function time() public view returns (uint) {
        return block.number;
    }

    function getJudge() public view virtual returns (address winner) {

        return _judgeAddress;

    }

    function getWinner() public view virtual returns (address winner) {
        return _winnerAddress;
    }

    function getWinningPrice() public view returns (uint price) {
        return _winningPrice;
    }

    function _ensureAuctionResolved() internal virtual {
        require(_winnerAddress != address(0), "Auction: winner not determined");
    }

    function _transferAllNFTs(address recipient) internal {
        if (!_nftContractDeclared || recipient == address(0)) {
            return;
        }

        uint256 length = _heldTokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = _heldTokenIds[i];
            _nftContract.safeTransferFrom(address(this), recipient, tokenId);
        }

        delete _heldTokenIds;
    }

    // If no judge is specified, anybody can call this.
    // If a judge is specified, then only the judge or winning bidder may call.
    function finalize() public virtual {

        _ensureAuctionResolved();
        require(!_settled, "Auction: already settled");

        if (_judgeDeclared) {
            require(msg.sender == _judgeAddress || msg.sender == _winnerAddress, "Auction: unauthorized finalize");
        }

        _settled = true;
        _refunded = false;

        if (_winningPrice > 0) {
            _pendingWithdrawals[_sellerAddress] += _winningPrice;
        }

        _transferAllNFTs(_winnerAddress);

    }

    // This can ONLY be called by seller or the judge (if a judge exists).
    // Money should only be refunded to the winner.
    function refund() public virtual {

        _ensureAuctionResolved();
        require(!_settled, "Auction: already settled");

        if (_judgeDeclared) {
            require(msg.sender == _judgeAddress || msg.sender == _sellerAddress, "Auction: unauthorized refund");
        } else {
            require(msg.sender == _sellerAddress, "Auction: only seller");
        }

        _settled = true;
        _refunded = true;

        if (_winningPrice > 0) {
            _pendingWithdrawals[_winnerAddress] += _winningPrice;
        }

        _transferAllNFTs(_sellerAddress);

    }

    // Withdraw funds from the contract.
    // If called, all funds available to the caller should be refunded.
    // This should be the *only* place the contract ever transfers funds out.
    // Ensure that your withdrawal functionality is not vulnerable to
    // re-entrancy or unchecked-error vulnerabilities.
    function withdraw() public {

        uint256 amount = _pendingWithdrawals[msg.sender];
        if (amount == 0) {
            return;
        }

        _pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Auction: withdrawal failed");

    }


    // This function is called whenever an NFT is transferred to this contract via safeTransferFrom
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenID,
        bytes calldata data
    ) external override returns (bytes4) {
    
        // Emit an event confirming receipt
        emit NFTReceived(operator, from, tokenID, data);

        require(_nftContractDeclared, "Auction: NFT contract not set");
        require(msg.sender == address(_nftContract), "Auction: unrecognized NFT");

        _heldTokenIds.push(tokenID);

        // Must return this selector to confirm receipt
        return IERC721Receiver.onERC721Received.selector;
    }

}
