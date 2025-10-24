// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Auction.sol";

contract EnglishAuction is Auction {

    uint public initialPrice;
    uint public biddingPeriod;
    uint public minimumPriceIncrement;

    bool internal _hasBid;
    address internal _currentLeader;
    uint internal _currentBid;
    uint internal _lastBidBlock;
    bool internal _resultComputed;

    // constructor
    constructor(address sellerAddress_,
                          uint initialPrice_,
                          uint biddingPeriod_,
                          uint minimumPriceIncrement_)
             Auction (sellerAddress_) {

        initialPrice = initialPrice_;
        biddingPeriod = biddingPeriod_;
        minimumPriceIncrement = minimumPriceIncrement_;
        _hasBid = false;
        _currentLeader = address(0);
        _currentBid = 0;
        _lastBidBlock = time();
        _resultComputed = false;
    }

    function bid() public payable{

        require(!_resultComputed && !_settled, "EnglishAuction: finalized");

        uint currentBlock = time();

        if (_hasBid) {
            require(currentBlock <= _lastBidBlock + biddingPeriod, "EnglishAuction: bidding closed");
            require(msg.value >= _currentBid + minimumPriceIncrement, "EnglishAuction: bid too low");

            address previousLeader = _currentLeader;
            uint previousBid = _currentBid;
            _pendingWithdrawals[previousLeader] += previousBid;

            _currentLeader = msg.sender;
            _currentBid = msg.value;
            _lastBidBlock = currentBlock;
        } else {
            require(msg.value >= initialPrice, "EnglishAuction: below reserve");

            _hasBid = true;
            _currentLeader = msg.sender;
            _currentBid = msg.value;
            _lastBidBlock = currentBlock;
        }

    }

    // Need to override the default implementation
    function getWinner() public override view returns (address winner){

        if (!_hasBid) {
            return address(0);
        }

        if (time() > _lastBidBlock + biddingPeriod || _resultComputed || _settled) {
            return _currentLeader;
        }

        return address(0);

    }

    function _ensureAuctionResolved() internal override {
        require(_hasBid, "EnglishAuction: no bids");
        require(time() > _lastBidBlock + biddingPeriod, "EnglishAuction: bidding ongoing");

        if (!_resultComputed) {
            _winnerAddress = _currentLeader;
            _winningPrice = _currentBid;
            _resultComputed = true;
        }
    }
}
