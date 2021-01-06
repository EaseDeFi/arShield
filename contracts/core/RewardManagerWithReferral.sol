// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import '../general/Ownable.sol';
import '../general/VaultTokenWrapper.sol';
import '../libraries/Math.sol';
import '../libraries/SafeMath.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IStakeManager.sol';
import '../interfaces/IRewardDistributionRecipient.sol';
/**
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

abstract contract RewardManagerWithReferral is VaultTokenWrapper, Ownable, IRewardDistributionRecipient {
    
    IERC20 public rewardToken;
    IStakeManager public stakeManager;
    address public rewardDistribution;
    uint256 public constant DURATION = 7 days;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    // Denominator used to when distributing tokens 1000 == 100%
    uint256 public constant DENOMINATOR = 1000;

    
    // Last time that a user transferred funds--used to keep track of fees owed by users.
    mapping (address => uint256) public lastUpdate;
    
    // Referrers of users get paid a % of what 
    mapping (address => address) public referrers;

    // Percent of fee that referrers receive. 50 == 5%.
    uint256 public referPercent;

    // Rate that will be paid (in %) per second for users using vault.
    // 1% == 1e18. Will start at 133164236000 for about 4.2% per year.
    uint256 public feePerSec;

    /**
     * @dev This modifier added by Armor to pay for insurance.
     * @param account The account that we're updating balance of.
    **/
    modifier updateBalance(address account)
    {
        if (lastUpdate[account] != 0) {
            uint256 timeElapsed = block.timestamp.sub(lastUpdate[account]);
            uint256 percent = feePerSec * timeElapsed;
            //guard for more than 100%
            if(percent > 1e20) {
                percent = 1e20;
            }
            // 1e20 = 1e18 because percent is in that many decimals + 100 because it's a percent.
            uint256 fee = (balanceOf(account) * percent) / 1e20;
            uint256 referFee = (fee * referPercent) / DENOMINATOR;
            _distributeFee(account, referrers[account], fee.sub(referFee), referFee);
        }
        lastUpdate[account] = block.timestamp;
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyRewardDistribution() {
        require(msg.sender == rewardDistribution, "Caller is not reward distribution");
        _;
    }

    /**
     * @dev Initialize Reward Manager.
     * @param _rewardToken The token that stakers will be rewarded with (ARMOR).
     * @param _stakeToken The token that will be being staked (LP for Uniswap or Balancer).
     * @param _rewardDistribution The address that will be sending ARMOR to this contract.
     * @param _feePerSec The % fee per second that will be charged to users. 1% = 1e18.
    **/
    function rewardInitialize(address _rewardToken, address _stakeToken, address _rewardDistribution, uint256 _feePerSec, uint256 _referPercent)
      internal
    {
        Ownable.initializeOwnable();
        initializeVaultTokenWrapper(_stakeToken);
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
        rewardDistribution = _rewardDistribution;
        feePerSec = _feePerSec;
        referPercent = _referPercent;
    }

    function setRewardDistribution(address _rewardDistribution)
        external
        override
        onlyOwner
    {
        rewardDistribution = _rewardDistribution;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    // Referrer will only set once. If it is address(0) upon first stake, it is set to devWallet.
    function stake(uint256 amount, address _referrer) public virtual updateBalance(msg.sender) updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        if ( referrers[msg.sender] == address(0) ) {
            referrers[msg.sender] = _referrer != address(0) ? _referrer : owner();
        }
        super._stake(msg.sender,amount);
        emit Staked(msg.sender, amount);
    }

    function _withdraw(address payable user, uint256 amount) internal {
        super._withdraw(user, amount);
        
        emit Withdrawn(user, amount);
    }

    function withdraw(uint256 amount) external virtual updateBalance(msg.sender) updateReward(msg.sender){
        require(amount > 0, "Cannot withdraw 0");
        RewardManagerWithReferral._withdraw(msg.sender, amount);
    }

    function exit() external virtual updateBalance(msg.sender) updateReward(msg.sender){
        uint256 amount = balanceOf(msg.sender);
        RewardManagerWithReferral._withdraw(msg.sender, amount);
        getReward();
    }

    function getReward() public updateBalance(msg.sender) updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function notifyRewardAmount(uint256 reward)
        external
        payable
        override
        onlyRewardDistribution
        updateReward(address(0))
    {
        //this will make sure tokens are in the reward pool
        if ( address(rewardToken) == address(0) ) require(msg.value == reward, "Correct reward was not sent.");
        else rewardToken.safeTransferFrom(msg.sender, address(this), reward);
        
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(DURATION);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(DURATION);
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(DURATION);
        emit RewardAdded(reward);
    }
    
    
    /**
     * @dev Owner may change the percent of insurance fees referrers receive.
     * @param _referPercent The percent of fees referrers receive. 50 == 5%.
    **/
    function changeReferPercent(uint256 _referPercent)
      external
      onlyOwner
    {
        require(_referPercent <= 1000, "Cannot give more than 100% of fees.");
        referPercent = _referPercent;
    }
    
}