// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Auction.sol";

contract VickreyAuction is Auction {

    uint public minimumPrice;
    uint public biddingDeadline;
    uint public revealDeadline;
    uint public bidDepositAmount;

    struct BidInfo {
        bytes32 commitment;
        bool hasCommitted;
        bool revealed;
        uint bidValue;
        bool validBid;
    }

    mapping(address => BidInfo) internal _bids;
    address[] internal _bidderList;

    uint internal _auctionStartBlock;
    address internal _highestBidder;
    uint internal _highestBid;
    uint internal _secondHighestBid;
    bool internal _resolutionComputed;
    bool internal _payoutsDistributed;

    // constructor
    constructor(address sellerAddress_,
                            uint minimumPrice_,
                            uint biddingPeriod_,
                            uint revealPeriod_,
                            uint bidDepositAmount_)
             Auction (sellerAddress_) {

        minimumPrice = minimumPrice_;
        bidDepositAmount = bidDepositAmount_;
        _auctionStartBlock = time();
        biddingDeadline = _auctionStartBlock + biddingPeriod_;
        revealDeadline = biddingDeadline + revealPeriod_;
        _highestBidder = address(0);
        _highestBid = 0;
        _secondHighestBid = 0;
        _resolutionComputed = false;
        _payoutsDistributed = false;

    }

    // Record the player's bid commitment
    // Make sure exactly bidDepositAmount is provided (for new bids)
    // Bidders can update their previous bid for free if desired.
    // Only allow commitments before biddingDeadline
    function commitBid(bytes32 bidCommitment) public payable {

        require(time() < biddingDeadline, "VickreyAuction: bidding closed");

        BidInfo storage info = _bids[msg.sender];

        if (!info.hasCommitted) {
            require(msg.value == bidDepositAmount, "VickreyAuction: incorrect deposit");
            info.hasCommitted = true;
            _bidderList.push(msg.sender);
        } else {
            require(msg.value == 0, "VickreyAuction: deposit already provided");
        }

        info.commitment = bidCommitment;

    }

    // Check that the bid (msg.value) matches the commitment.
    // If the bid is correctly opened, the bidder can withdraw their deposit.
    function revealBid(uint nonce) public payable{

        require(time() >= biddingDeadline, "VickreyAuction: reveal too early");
        require(time() < revealDeadline, "VickreyAuction: reveal period over");

        BidInfo storage info = _bids[msg.sender];
        require(info.hasCommitted, "VickreyAuction: no commitment");
        require(!info.revealed, "VickreyAuction: already revealed");

        bytes32 expected = keccak256(abi.encodePacked(msg.value, nonce));
        require(expected == info.commitment, "VickreyAuction: commitment mismatch");

        info.revealed = true;
        info.bidValue = msg.value;
        info.validBid = msg.value >= minimumPrice;

        _pendingWithdrawals[msg.sender] += bidDepositAmount;

        if (info.validBid) {
            if (msg.value > _highestBid) {
                _secondHighestBid = _highestBid;
                _highestBid = msg.value;
                _highestBidder = msg.sender;
            } else if (msg.value > _secondHighestBid) {
                _secondHighestBid = msg.value;
            }
        }

    }

    // Need to override the default implementation
    function getWinner() public override view returns (address winner){

        if (_resolutionComputed || _settled) {
            return _winnerAddress;
        }

        if (time() >= revealDeadline) {
            return _highestBidder;
        }

        return address(0);

    }

    // finalize() must be extended here to provide a refund to the winner
    // based on the final sale price (the second highest bid, or reserve price).
    function finalize() public override {

        _ensureAuctionResolved();
        _distributeBidFunds();
        super.finalize();

    }

    function refund() public override {
        _ensureAuctionResolved();
        _distributeBidFunds();
        super.refund();
    }

    function _ensureAuctionResolved() internal override {
        require(time() >= revealDeadline, "VickreyAuction: reveal phase active");
        require(_highestBidder != address(0), "VickreyAuction: no valid bids");

        if (!_resolutionComputed) {
            _winnerAddress = _highestBidder;
            uint price = _secondHighestBid;
            if (price < minimumPrice) {
                price = minimumPrice;
            }
            _winningPrice = price;
            _resolutionComputed = true;
        }
    }

    function _distributeBidFunds() internal {
        if (_payoutsDistributed) {
            return;
        }

        for (uint i = 0; i < _bidderList.length; i++) {
            address bidder = _bidderList[i];
            BidInfo storage info = _bids[bidder];

            if (!info.revealed) {
                _pendingWithdrawals[_sellerAddress] += bidDepositAmount;
                continue;
            }

            if (info.validBid) {
                if (bidder == _winnerAddress) {
                    if (info.bidValue > _winningPrice) {
                        _pendingWithdrawals[bidder] += info.bidValue - _winningPrice;
                    }
                } else {
                    _pendingWithdrawals[bidder] += info.bidValue;
                }
            } else {
                if (info.bidValue > 0) {
                    _pendingWithdrawals[bidder] += info.bidValue;
                }
            }
        }

        _payoutsDistributed = true;
    }
}
