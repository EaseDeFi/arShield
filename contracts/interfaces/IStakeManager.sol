// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IStakeManager {
    function totalStakedAmount(address protocol) external view returns(uint256);
    function protocolAddress(uint64 id) external view returns(address);
    function protocolId(address protocol) external view returns(uint64);
    function initialize(address _armorMaster) external;
    function allowedCover(address _newProtocol, uint256 _newTotalCover) external view returns (bool);
    function subtractTotal(uint256 _nftId, address _protocol, uint256 _subtractAmount) external;
}
