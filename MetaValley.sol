// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract MetaValley{


    using SafeMath for uint256;

    uint256 public CRYSTALS_TO_HATCH_1WORKERS=864000;
    uint256 private MARKETING_FEE = 15;
    uint256 private CEO_FEE = 8;
    uint256 private CTO_FEE = 7;
    uint256 private RESTAKE = 15;
    uint256 private REFERRAL = 13;

    uint256 PSN=10000;
    uint256 PSNH=5000;
    
    bool public initialized=false;
    address private ceoAddress;
    address private ctoAddress;
    address private marketingTreasury;
    address private admin;
    address private stable;
    mapping (address => uint256) public hatcheryWorkers;
    mapping (address => uint256) public claimedCrystals;
    mapping (address => uint256) public lastHatch;
    mapping (address => address) public referrals;
    uint256 public marketCrystals;

    event Buy(address indexed who, uint256 minerBought);
    event Sell(address indexed who, uint256 crystalSold, uint256 tokenEarned);
    event Compound(address indexed who, uint256 rewards, uint256 minerBought);

    constructor(address ceo, address marketing, address _stable) {
        ctoAddress = msg.sender;
        ceoAddress = ceo;
        marketingTreasury = marketing;
        admin = msg.sender;
        stable = _stable;
    }

    function hatchCrystals(address ref) public{
        require(initialized, 'NOT_INITIALIZED_YET');

        if(ref == msg.sender || ref == address(0) || hatcheryWorkers[ref] == 0) {
            ref = ceoAddress;
        }

        if(referrals[msg.sender] == address(0)){
            referrals[msg.sender] = ref;
        }

        uint256 crystalsUsed=getMyCrystals();
        uint256 newWorkers=SafeMath.div(crystalsUsed,CRYSTALS_TO_HATCH_1WORKERS);
        hatcheryWorkers[msg.sender]=SafeMath.add(hatcheryWorkers[msg.sender],newWorkers);
        claimedCrystals[msg.sender]=0;
        lastHatch[msg.sender]=block.timestamp;

        //send referral crystals
        claimedCrystals[referrals[msg.sender]] = SafeMath.add(
            claimedCrystals[referrals[msg.sender]],
            SafeMath.div(
                SafeMath.mul(crystalsUsed, REFERRAL),
                100
            )
        );

        //boost market to nerf workers hoarding
        marketCrystals = SafeMath.add( marketCrystals, SafeMath.div(crystalsUsed,5));

        emit Buy(msg.sender, newWorkers);

    }

    function sellCrystals() public{
        require(initialized, 'NOT_INITIALIZED_YET');

        uint256 hasCrystals=getMyCrystals();
        uint256 crystalValue=calculateCrystalSell(hasCrystals);
        require(crystalValue > 0, "invalid crystalValue");

        uint256 _ceoFee = ceoFee(crystalValue);
        uint256 _ctoFee = ctoFee(crystalValue);
        uint256 _treasuryFee = treasuryFee(crystalValue);

        claimedCrystals[msg.sender]=0;
        lastHatch[msg.sender]=block.timestamp;
        marketCrystals=SafeMath.add(marketCrystals,hasCrystals);

        IERC20(stable).transfer(ceoAddress, _ceoFee);
        IERC20(stable).transfer(ctoAddress, _ctoFee);
        IERC20(stable).transfer(marketingTreasury, _treasuryFee);

        uint256 amount = SafeMath.sub( crystalValue, sum(_ceoFee, _ctoFee, _treasuryFee));
        uint256 autoCompound = SafeMath.div( SafeMath.mul(RESTAKE, amount), 100);
        amount = SafeMath.sub(amount, autoCompound);
        uint256 crystalsBought = calculateCrystalBuy(autoCompound, SafeMath.sub(getBalance(), autoCompound));

        crystalsBought = SafeMath.sub(
            crystalsBought,
            sum(
                ceoFee(crystalsBought),
                ctoFee(crystalsBought),
                treasuryFee(crystalsBought)
            )
        );
        
        uint256 _ceoFee2 = ceoFee(crystalsBought);
        uint256 _ctoFee2 = ctoFee(crystalsBought);
        uint256 _treasuryFee2 = treasuryFee(crystalsBought);

        IERC20(stable).transfer(ceoAddress, _ceoFee2);
        IERC20(stable).transfer(ctoAddress, _ctoFee2);
        IERC20(stable).transfer(marketingTreasury, _treasuryFee2);

        claimedCrystals[msg.sender]=SafeMath.add(claimedCrystals[msg.sender],crystalsBought);
        hatchCrystals(referrals[msg.sender]);

        IERC20(stable).transfer(msg.sender, amount);
        emit Sell(msg.sender, hasCrystals, crystalValue);
    }

    function buyCrystals(address ref, uint256 amount) public {

        require(initialized, 'NOT_INITIALIZED_YET');
        require( IERC20(stable).balanceOf(msg.sender) >= amount, 'INSUFFICENT_BALANCE');
        require( IERC20(stable).allowance(msg.sender, address(this)) >= amount, 'INSUFFICENT_ALLOWANCE');

        uint256 crystalsBought = calculateCrystalBuy(amount, SafeMath.sub(getBalance(), amount));
        crystalsBought = SafeMath.sub( crystalsBought, sum(ceoFee(crystalsBought), ctoFee(crystalsBought), treasuryFee(crystalsBought)));
        uint256 _ceoFee = ceoFee(amount);
        uint256 _ctoFee = ctoFee(amount);
        uint256 _treasuryFee = treasuryFee(amount);
        IERC20(stable).transferFrom(msg.sender, address(this), amount);
        IERC20(stable).transfer(ceoAddress, _ceoFee);
        IERC20(stable).transfer(ctoAddress, _ctoFee);
        IERC20(stable).transfer(marketingTreasury, _treasuryFee);
        claimedCrystals[msg.sender] = SafeMath.add(claimedCrystals[msg.sender], crystalsBought);
        hatchCrystals(ref);
    }

    function seedMarket(uint256 seedAmount) public {
        require(msg.sender == ctoAddress || msg.sender == admin, 'unallowed');
        require(seedAmount > 0, 'ZERO_AMOUNT');
        require(marketCrystals == 0, 'INITIALIZED');
        initialized=true;
        marketCrystals=86400000000;
        uint256 iAmount = seedAmount.div(2);
        IERC20(stable).transferFrom(msg.sender, address(this), iAmount);
        buyCrystals(msg.sender, seedAmount - iAmount);
    }

    function calculateTrade(uint256 rt,uint256 rs, uint256 bs) public view returns(uint256){
        //(PSN*bs)/(PSNH+((PSN*rs+PSNH*rt)/rt));
        return SafeMath.div(SafeMath.mul(PSN,bs),SafeMath.add(PSNH,SafeMath.div(SafeMath.add(SafeMath.mul(PSN,rs),SafeMath.mul(PSNH,rt)),rt)));
    }

    function calculateCrystalSell(uint256 crystals) public view returns(uint256){
        return calculateTrade(crystals,marketCrystals,getBalance());
    }

    function calculateCrystalBuy(uint256 eth,uint256 contractBalance) public view returns(uint256){
        return calculateTrade(eth,contractBalance,marketCrystals);
    }
    
    function calculateCrystalBuySimple(uint256 eth) public view returns(uint256){
        return calculateCrystalBuy(eth,getBalance());
    }

    function ctoFee(uint256 amount) public view returns(uint256){
        return SafeMath.div(SafeMath.mul(amount, CTO_FEE),1000);
    }

    function ceoFee(uint256 amount) public view returns(uint256){
        return SafeMath.div(SafeMath.mul(amount, CEO_FEE),1000);
    }

    function treasuryFee(uint256 amount) public view returns(uint256){
        return SafeMath.div(SafeMath.mul(amount,MARKETING_FEE),1000);
    }

    function getBalance() public view returns(uint256){
        return IERC20(stable).balanceOf(address(this));
    }

    function getMyWorkers() public view returns(uint256){
        return hatcheryWorkers[msg.sender];
    }

    function getMyCrystals() public view returns(uint256){
        return SafeMath.add(claimedCrystals[msg.sender],getCrystalsSinceLastHatch(msg.sender));
    }

    function getCrystalsSinceLastHatch(address adr) public view returns(uint256){
        uint256 secondsPassed=min(CRYSTALS_TO_HATCH_1WORKERS,SafeMath.sub(block.timestamp,lastHatch[adr]));
        return SafeMath.mul(secondsPassed,hatcheryWorkers[adr]);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function sum(uint256 a, uint256 b, uint256 c) private pure returns(uint256) {
        return SafeMath.add(SafeMath.add(a, b), c);
    }
}