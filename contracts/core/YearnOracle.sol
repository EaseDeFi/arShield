// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import './IYearnV2.sol';
import '../interfaces/AggregatorV3Interface.sol';

/**
 * @dev Uses Chainlink to find the price of underlying Yearn assets,
 *      then determines amount of yTokens to pay for Ether needed by shield.
**/
contract YearnOracle {

    /**
     * @dev Get the amount of tokens owed for the input amount of Ether.
     * @param _ethOwed Amount of Ether that the shield owes to coverage base.
     * @param _yToken Address of the Yearn token to find value of.
     * @param _uTokenLink Chainlink address to get price of the underlying token.
    **/
    function getTokensOwed(
        uint256 _ethOwed,
        address _yToken,
        address _uTokenLink
    )
      external
      view
    returns(
        uint256 yOwed
    )
    {   
        uint256 uOwed = ethToU(ethOwed, _uTokenLink);
        yOwed = uToY(_yToken, uOwed);
    }
    
    /**
     * @dev Ether amount to underlying token owed.
     * @param _ethOwed Amount of Ether owed to the coverage base.
     * @param _uTokenLink Chainlink oracle address for the underlying token.
     * @return uOwed Amount of underlying tokens owed.
    **/
    function ethToU(
        uint256 _ethOwed,
        address _uTokenLink
    )
      public
      view
    returns(
        uint256 uOwed
    )
    {
        uint256 ethPerToken = _findEthPerToken(_uTokenLink);
        uOwed = _ethOwed * 1 ether / ethPerToken;
    }

    /**
     * @dev Underlying tokens to Yearn tokens conversion.
     * @param _yToken Address of the Yearn token.
     * @param _uOwed Amount of underlying tokens owed.
     * @return yOwed Amount of Yearn tokens owed.
    **/
    function uToY(
        address _yToken,
        uint256 _uOwed
    )
      public
      view
    returns(
        uint256 yOwed
    )
    {
        uint256 oneYToken = IYearnV2(_yToken).pricePerShare();
        yOwed = _uOwed * (10 ** IYearnV2(_yToken).decimals()) / oneYToken;
    }
    
    /**
     * @dev Finds the amount of cover required to protect all holdings and returns Ether value of 1 token.
     * @param _uTokenLink Chainlink oracle address for the underlying token.
     * @return ethPerToken Ether value of each pToken.
    **/
    function _findEthPerToken(
        address _uTokenLink
    )
      internal
    returns (
        uint256 ethPerToken
    )
    {
        (/*roundIf*/, int tokenPrice, /*startedAt*/, /*timestamp*/, /*answeredInRound*/) = AggregatorV3Interface(_uTokenLink).latestAnswer();
        ethPerToken = uint256(tokenPrice);
    }
    
}