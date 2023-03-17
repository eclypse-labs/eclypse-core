pragma solidity >=0.6.11;

interface IPriceFeed {
    // --- Events ---
    event TokenAddedToPool(address _token, address _pool, uint256 _time);
    event LastGoodPriceUpdated(uint256 _lastGoodPrice);
    event PriceFeedStatusChanged(OracleStatus newStatus);

    struct PoolPricingInfo {
        address poolAddress;
        bool inv; // true if and only if WETH is token0 of the pool.
    }

    enum OracleStatus {
        UniV3TWAPworking,
        chainlinkWorking,
        bothOraclesDown
    }

    // --- Functions---
    function fetchPrice(address _tokenAddress) external returns (uint256);
    function fetchDollarPrice(address token) external returns (uint);

}
