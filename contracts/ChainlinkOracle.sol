pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./CToken.sol";
import "./CErc20.sol";
import "./PriceOracle.sol";
import "./ERC20Interface.sol";
import "./AggregatorV2V3Interface.sol";

contract SteakBankImpl {
    uint256 public lbnbToBNBExchangeRate;
}

contract ChainlinkOracle is PriceOracle {
    using SafeMath for uint;
    
    address public admin;

    mapping(address => uint) internal prices;
    mapping(bytes32 => AggregatorV2V3Interface) internal feeds;
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);
    event NewAdmin(address oldAdmin, address newAdmin);
    event FeedSet(address feed, string symbol);

    SteakBankImpl public sbfImpl;

    constructor() public {
        admin = msg.sender;
        sbfImpl = SteakBankImpl(0x79DB0dAa012F4b98F332A9D45c80A1A3FFaa6f9a);
    }

    function getUnderlyingPrice(CToken cToken) public view returns (uint) {
        string memory symbol = cToken.symbol();
        if (compareStrings(symbol, "sBNB")) {
            return getChainlinkPrice(getFeed(symbol));
        } else if (compareStrings(symbol, "sLBNB")) {
            uint256 bnbPrice = getChainlinkPrice(getFeed("sBNB"));
            uint256 lbnbRate = sbfImpl.lbnbToBNBExchangeRate();
            return bnbPrice * lbnbRate / (10**9);
        } else {
            return getPrice(cToken);
        }
    }

    function getPrice(CToken cToken) internal view returns (uint price) {
        string memory symbol = cToken.symbol();
        ERC20Interface token = ERC20Interface(CErc20(address(cToken)).underlying());

        if (prices[address(token)] != 0) {
            price = prices[address(token)];
        } else {
            price = getChainlinkPrice(getFeed(symbol));
        }

        uint decimalDelta = uint(18).sub(uint(token.decimals()));
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            return price.mul(10**decimalDelta);
        } else {
            return price;
        }
    }

    function getChainlinkPrice(AggregatorV2V3Interface feed) internal view returns (uint) {
        // Chainlink USD-denominated feeds store answers at 8 decimals
        uint decimalDelta = uint(18).sub(feed.decimals());
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            return uint(feed.latestAnswer()).mul(10**decimalDelta);
        } else {
            return uint(feed.latestAnswer());
        }
    }

    function setUnderlyingPrice(CToken cToken, uint underlyingPriceMantissa) external onlyAdmin() {
        address asset = address(CErc20(address(cToken)).underlying());
        emit PricePosted(asset, prices[asset], underlyingPriceMantissa, underlyingPriceMantissa);
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint price) external onlyAdmin() {
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    function setFeed(string calldata symbol, address feed) external onlyAdmin() {
        require(feed != address(0) && feed != address(this), "invalid feed address");
        emit FeedSet(feed, symbol);
        feeds[keccak256(abi.encodePacked(symbol))] = AggregatorV2V3Interface(feed);
    }

    function getFeed(string memory symbol) public view returns (AggregatorV2V3Interface) {
        return feeds[keccak256(abi.encodePacked(symbol))];
    }

    function assetPrices(address asset) external view returns (uint) {
        return prices[asset];
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function setAdmin(address newAdmin) external onlyAdmin() {
        address oldAdmin = admin;
        admin = newAdmin;

        emit NewAdmin(oldAdmin, newAdmin);
    }

    modifier onlyAdmin() {
      require(msg.sender == admin, "only admin may call");
      _;
    }
}