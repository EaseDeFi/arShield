pragma solidity 0.6.12;
import '../client/ArmorClient.sol';
import '../general/Ownable.sol';

contract CoverageBase is ArmorClient, Ownable {
    
    // Denominator for coverage percent.
    uint256 public constant DENOMINATOR = 1000;
    // The protocol that this contract purchases coverage for.
    address public protocol;
    // Percent of funds from shields to cover.
    uint256 public coverPct;
    // Current cost per second for all Ether on contract.
    uint256 public totalCost;
    // Current cost per second per Ether.
    uint256 public costPerEth;
    // sum of cost per Ether for every second -- cumulative lol.
    uint256 public cumCost;
    // Last update of cumCost.
    uint256 public lastUpdate;
    // Total Ether value to be protecting in the contract.
    uint256 public totalEthValue;
    // Value in Ether and last updates of each shield vault.
    mapping (address => ShieldStats) public shieldStats;
    
    // Every time a shield updates it saves the full contracts cumulative cost, its Ether value, and 
    struct ShieldStats {
        uint256 lastCumCost;
        uint128 ethValue;
        uint128 lastUpdate;
    }
    
    /**
     * @dev Called by a keeper to update the amount covered by this contract on arCore.
    **/
    function updateCoverage()
      external
    {
        ArmorCore.subscribe( protocol, getCoverage() );
        totalCost = getCoverageCost();
        checkpoint();
    }
    
    /**
     * @dev arShield uses this to update the value of funds on their contract and deposit payments to here.
     *      We're okay with being loose-y goose-y here in terms of making sure shields pay (no cut-offs, timeframes, etc.).
     * @param _newEthValue The new Ether value of funds in the shield contract.
    **/
    function updateShield(
        uint256 _newEthValue
    )
      external
      payable
    {
        ShieldStats memory stats = shieldStats[msg.sender];
        require(stats.lastUpdate > 0, "Only arShields may access this function.");
        
        // Determine how much the shield owes for the last period.
        uint256 owed = getShieldOwed(msg.sender);
        require(msg.value >= owed, "Shield is not paying enough for the coverage provided.");
        
        totalEthValue = totalEthValue 
                        - uint256(stats.ethValue)
                        + _newEthValue;

        checkpoint();
        shieldStats[msg.sender] = ShieldStats( cumCost, uint128(_newEthValue), uint128(block.timestamp) );
    }
    
    /**
     * @dev CoverageBase tells shield what % of current coverage it must pay.
     * @param _shield Address of the shield to get owed amount for.
    **/
    function getShieldOwed(
        address _shield
    )
      public
      view
    returns(
        uint256 owed
    )
    {
        ShieldStats memory stats = shieldStats[_shield];
        
        // difference between current cumulative and cumulative at last shield update
        uint256 pastDiff = cumCost - stats.lastCumCost;
        uint256 currentDiff = costPerEth * ( block.timestamp - uint256(lastUpdate) );
        
        owed = uint256(stats.ethValue) 
                * pastDiff 
                + uint256(stats.ethValue)
                * currentDiff;
    }
    
    /**
     * @dev Record total values from last period and set new ones.
    **/
    function checkpoint()
      internal
    {
        cumCost += costPerEth * (block.timestamp - lastUpdate);
        costPerEth = totalCost * 1 ether / totalEthValue;
        lastUpdate = block.timestamp;
    }
    
    /**
     * @dev Get the amount of coverage for all shields' current values.
    **/
    function getCoverage()
      public
      view
    returns (
        uint256
    )
    {
        return totalEthValue * coverPct / DENOMINATOR;
    }
    
    /**
     * @dev Get the cost of coverage for all shields' current values.
    **/
    function getCoverageCost()
      public
      view
    returns (
        uint256
    )
    {
        return ArmorCore.calculatePricePerSec( protocol, getCoverage() );
    }
    
    /**
     * @dev Either add or delete a shield.
     * @param _shield Address of the shield to edit.
     * @param _active Whether we want it to be added or deleted.
    **/
    function editShield(
        address _shield,
        bool _active
    )
      external
      onlyOwner
    {
        // If active, set timestamp of last update to now, else delete.
        if (_active) shieldStats[_shield] = ShieldStats( cumCost, 0, uint128(block.timestamp) );
        else delete shieldStats[_shield]; 
    }
    
    /**
     * @dev Cancel entire arCore plan.
    **/
    function cancelCoverage()
      external
      onlyOwner
    {
        ArmorCore.cancelPlan();
    }
    
    /**
     * @dev Governance may call to a redeem a claim for Ether that this contract held.
     * @param _hackTime Time that the hack occurred.
     * @param _amount Amount of funds to be redeemed.
    **/
    function redeemClaim(
        uint256 _hackTime,
        uint256 _amount
    )
      external
      onlyOwner
    {
        ArmorCore.claim(protocol, _hackTime, _amount);
    }
    
    /**
     * @dev Governance may disburse funds from a claim to the chosen shields.
     * @param _shield Address of the shield to disburse funds to.
     * @param _amount Amount of funds to disburse to the shield.
    **/
    function disburseClaim(
        address payable _shield,
        uint256 _amount
    )
      external
      onlyOwner
    {
        require(shieldStats[_shield].lastUpdate > 0, "Shield is not authorized to use this contract.");
        _shield.transfer(_amount);
    }
    
    /**
     * @dev Change the percent of coverage that should be bought. For example, 500 means that 50% of Ether value will be covered.
     * @param _newPct New percent of coverage to be bought--1000 == 100%.
    **/
    function changeCoverPct(
        uint256 _newPct
    )
      external
      onlyOwner
    {
        require(_newPct <= 1000, "Coverage percent may not be greater than 100%.");
        coverPct = _newPct;    
    }
    
}
