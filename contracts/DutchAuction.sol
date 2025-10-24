// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Auction.sol";

contract DutchAuction is Auction {

    uint public initialPrice;
    uint public biddingPeriod;
    uint public offerPriceDecrement;

    uint internal _auctionStartBlock;
    bool internal _auctionResolved;

    // constructor
    constructor(address sellerAddress_,
                          uint initialPrice_,
                          uint biddingPeriod_,
                          uint offerPriceDecrement_)
             Auction (sellerAddress_) {

        initialPrice = initialPrice_;
        biddingPeriod = biddingPeriod_;
        offerPriceDecrement = offerPriceDecrement_;
        _auctionStartBlock = time();
        _auctionResolved = false;

    }


    function bid() public payable{

        require(_winnerAddress == address(0), "DutchAuction: already won");

        uint currentBlock = time();
        require(currentBlock < _auctionStartBlock + biddingPeriod, "DutchAuction: bidding period over");

        uint currentPrice = _currentPrice(currentBlock);
        require(msg.value >= currentPrice, "DutchAuction: insufficient bid");

        _winnerAddress = msg.sender;
        _winningPrice = currentPrice;
        _auctionResolved = true;

        if (msg.value > currentPrice) {
            _pendingWithdrawals[msg.sender] += msg.value - currentPrice;
        }

    }

    function _currentPrice(uint currentBlock) internal view returns (uint) {
        if (currentBlock <= _auctionStartBlock) {
            return initialPrice;
        }

        uint elapsed = currentBlock - _auctionStartBlock;
        uint decrement = elapsed * offerPriceDecrement;

        if (decrement >= initialPrice) {
            return 0;
        }

        return initialPrice - decrement;
    }

}
