// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "hardhat/console.sol";


contract BullnBear is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable, KeeperCompatibleInterface, VRFConsumerBaseV2 {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    uint public /*immutable*/ interval;
    uint public lastTimeStamp;

    AggregatorV3Interface public priceFeed;
    int256 public currentPrice = 0;

    // VRF
    VRFCoordinatorV2Interface public COORDINATOR;
    uint256[] public s_randomWords;
    uint256 public s_requestId;
    uint32 public callbackGasLimit = 500000; // set higher as fulfillRandomWords is doing a LOT of heavy lifting.
    uint64 public s_subscriptionId;
    bytes32 keyhash =  0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc; // keyhash, see for Rinkeby https://docs.chain.link/docs/vrf-contracts/#rinkeby-testnet
    
    enum MarketTrend{BULL, BEAR}
    MarketTrend public currentMarketTrend = MarketTrend.BULL; 

    string[] bullUrisIpfs = [
        "https://ipfs.io/ipfs/QmRXyfi3oNZCubDxiVFre3kLZ8XeGt6pQsnAQRZ7akhSNs?filename=gamer_bull.json",
        "https://ipfs.io/ipfs/QmRJVFeMrtYS2CUVUM2cHJpBV5aX2xurpnsfZxLTTQbiD3?filename=party_bull.json",
        "https://ipfs.io/ipfs/QmdcURmN1kEEtKgnbkVJJ8hrmsSWHpZvLkRgsKKoiWvW9g?filename=simple_bull.json"
    ];

    string[] bearUrisIpfs = [
        "https://ipfs.io/ipfs/Qmdx9Hx7FCDZGExyjLR6vYcnutUR8KhBZBnZfAPHiUommN?filename=beanie_bear.json",
        "https://ipfs.io/ipfs/QmTVLyTSuiKGUEmb88BgXG3qNC8YgpHZiFbjHrXKH3QHEu?filename=coolio_bear.json",
        "https://ipfs.io/ipfs/QmbKhBXVWmwrYsTPFYfroR2N7NAekAMxHUVg2CWks7i9qj?filename=simple_bear.json"
    ];

    event TokensUpdated(string marketTrend);


    constructor(uint updateInterval, address _priceFeed, address _vrfCoordinator) ERC721("BullnBear", "BNBT") VRFConsumerBaseV2(_vrfCoordinator) {
        // Sets the keeper update interval
        interval = updateInterval;
        lastTimeStamp = block.timestamp;

        // Pricefeed contract : https://rinkeby.etherscan.io/address/0xECe365B379E1dD183B20fc5f022230C044d51404
        priceFeed = AggregatorV3Interface(_priceFeed);
        currentPrice = getLatestPrice();
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);  
    }

    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        // Defaults to Gamer Bull
        string memory defaultUri = bullUrisIpfs[0];
        _setTokenURI(tokenId, defaultUri);
    }

    function setInterval(uint newInterval) public onlyOwner {
        interval = newInterval;
    }

    function setPriceFeed(address newFeed) public onlyOwner {
        priceFeed = AggregatorV3Interface(newFeed);
    }
    // Helpers
    function compareStrings(string memory a, string memory b) internal pure returns (bool){
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    // function updateAllTokenUris(string memory trend) internal {
    //     if (compareStrings("bear",trend)) {
    //         for(uint i = 0; i < _tokenIdCounter.current(); i++){
    //             _setTokenURI(i,bearUrisIpfs[0]);
    //         }
    //     }
    //     else {
    //         for(uint i = 0; i < _tokenIdCounter.current(); i++){
    //             _setTokenURI(i,bullUrisIpfs[0]);
    //         }
    //     }

    //     emit TokensUpdated(trend);
        
    // }

    function checkUpkeep(bytes calldata /* checkData */) external view override returns (bool upkeepNeeded, bytes memory /* performData */) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        //We highly recommend revalidating the upkeep in the performUpkeep function
        if ((block.timestamp - lastTimeStamp) > interval ) {
            lastTimeStamp = block.timestamp;         
            int latestPrice =  getLatestPrice(); 
        
            if (latestPrice == currentPrice) {
                console.log("NO CHANGE -> returning!");
                return;
            }

            if (latestPrice < currentPrice) {
                // bear
                currentMarketTrend = MarketTrend.BEAR;
            } else {
                // bull
                currentMarketTrend = MarketTrend.BULL;
            }

            // Initiate the VRF calls to get a random number (word)
            // that will then be used to to choose one of the URIs 
            // that gets applied to all minted tokens.
            requestRandomnessForNFTUris();
            // update currentPrice
            currentPrice = latestPrice;
        } else {
            // Nothing.
            return;
        }
    }

    function requestRandomnessForNFTUris() internal {
        require(s_subscriptionId != 0, "Subscription ID not set"); 

        // Will revert if subscription is not set and funded.
        s_requestId = COORDINATOR.requestRandomWords(
            keyhash,
            s_subscriptionId,
            3,
            callbackGasLimit,
            1
        );

        console.log("Request ID: ", s_requestId);
    }

    // This is the callback that the VRF coordinator sends the 
    // random values to.
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;
        console.log("...Fulfilling random Words");
        string[] memory urisForTrend = currentMarketTrend == MarketTrend.BULL ? bullUrisIpfs : bearUrisIpfs;
        uint256 idx = randomWords[0] % urisForTrend.length; // use modulo to choose a random index.


        for (uint i = 0; i < _tokenIdCounter.current() ; i++) {
            _setTokenURI(i, urisForTrend[idx]);
        } 

        string memory trend = currentMarketTrend == MarketTrend.BULL ? "bullish" : "bearish";
        
        emit TokensUpdated(trend);
    }

      // For VRF Subscription Manager
    function setSubscriptionId(uint64 _id) public onlyOwner {
        s_subscriptionId = _id;
    }


    function setCallbackGasLimit(uint32 maxGas) public onlyOwner {
        callbackGasLimit = maxGas;
    }

    function setVrfCoodinator(address _address) public onlyOwner {
        COORDINATOR = VRFCoordinatorV2Interface(_address);
    }
        

    function getLatestPrice() public view returns (int256) {
        (
            /* uint80 roundId */,
            int price,
            /* uint256 startedAt */,
            /* uint256 updatedAt */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();

        return price;
    }


    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}