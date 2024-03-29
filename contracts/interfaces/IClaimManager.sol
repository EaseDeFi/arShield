// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IClaimManager {
    function initialize(address _armorMaster) external;
    function transferNft(address _to, uint256 _nftId) external;
    function exchangeWithdrawal(uint256 _amount) external;
    function redeemClaim(address _protocol, uint256 _hackTime, uint256 _amount) external;
}
