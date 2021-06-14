// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

abstract contract ReducingTaxToken is ERC20Burnable, Ownable {
    uint256 percentSupply75;
    uint256 percentSupply50;
    address public burnAccount = 0x000000000000000000000000000000000000dEaD;
    address public charityAccount;

    mapping (address => bool) public isExemptFromFee;

    constructor(uint256 _initialSupply, address _charityAccount) {
        percentSupply75 = (_initialSupply * 3) / 4; // 75% of the initial supply
        percentSupply50 = _initialSupply / 2; // 50% of the initial supply
        charityAccount = _charityAccount;
        isExemptFromFee[owner()] = true;
    }

    function calculateBurnFee(uint256 amount) public view returns (uint256) {
        uint256 circulatingSupply = totalSupply() - balanceOf(burnAccount);
        uint256 burnAmount;

        if (circulatingSupply > percentSupply75) {
            // burn 1%
            burnAmount = amount/100;
        } else if(circulatingSupply > percentSupply50) {
            // burn 0.5%
            burnAmount = amount/200;
            uint256 availableBurn = circulatingSupply - percentSupply50;
            if (burnAmount > availableBurn) {
                burnAmount = availableBurn;
            }
        }
        return burnAmount;
    }

    function calculateCharityFee(uint256 amount) public pure returns (uint256) {
        return amount/100;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        uint256 burnFee;
        uint256 charityFee;
        
        if(!isExemptFromFee[_msgSender()]) {
            burnFee = calculateBurnFee(amount);
            charityFee = calculateCharityFee(amount);
            _transfer(_msgSender(), burnAccount, burnFee);
            _transfer(_msgSender(), charityAccount, charityFee);
        }
        _transfer(_msgSender(), recipient, amount - burnFee - charityFee);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        uint256 burnFee;
        uint256 charityFee;
        if(!isExemptFromFee[sender]) {
            burnFee = calculateBurnFee(amount);
            charityFee = calculateCharityFee(amount);
            _transfer(sender, burnAccount, burnFee);
            _transfer(sender, charityAccount, charityFee);
        }
        _transfer(sender, recipient, amount - burnFee - charityFee);

        uint256 currentAllowance = allowance(sender, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function addFeeExemption(address user) external onlyOwner {
        isExemptFromFee[user] = true;
    }

    function removeFeeExemption(address user) external onlyOwner {
        isExemptFromFee[user] = false;
    }
}

abstract contract AntiWhaleToken is ReducingTaxToken {

    uint256 public maxTxAmount;
    uint256 public hotlistTxAmount;
    uint256 public cooldownPeriod;

    mapping (address => bool) public isExemptFromTxLimit;
    mapping (address => uint) public lastHotTxTime;

    constructor(uint256 _maxTxAmount, uint256 _hotlistTxAmount, uint256 _cooldownPeriod) {
        maxTxAmount = _maxTxAmount;
        hotlistTxAmount = _hotlistTxAmount;
        cooldownPeriod = _cooldownPeriod;

        isExemptFromTxLimit[address(0)] = true;
        isExemptFromTxLimit[owner()] = true;
    }

    function _checkAndUpdateLimits(address from, uint256 amount) internal {
        require (isExemptFromTxLimit[from]
                || amount <= maxTxAmount,
                "AWT: Exceeds max tx amount");
        if (!isExemptFromTxLimit[from] && amount > hotlistTxAmount) {
            require (block.timestamp >= lastHotTxTime[from] + cooldownPeriod, "AWT: Sender must wait for cooldown");
            lastHotTxTime[from] = block.timestamp;
        }
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _checkAndUpdateLimits(_msgSender(), amount);
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _checkAndUpdateLimits(sender, amount);
        return super.transferFrom(sender, recipient, amount);
    }

    function addTxLimitExemption(address user) external onlyOwner {
        isExemptFromTxLimit[user] = true;
    }

    function removeTxLimitExemption(address user) external onlyOwner {
        isExemptFromTxLimit[user] = false;
    }

    function updateMaxTxAmount(uint256 percentBIPS) external onlyOwner {
        require (percentBIPS >= 20 && percentBIPS <= 100, "AWT: MaxTxAmount out of range");
        maxTxAmount = (totalSupply() * percentBIPS) / 10000;
    }

    function updateHotlistTxAmount(uint256 percentBIPS) external onlyOwner {
        require (percentBIPS >= 10 && percentBIPS <= 50, "AWT: HotlistTxAmount out of range");
        hotlistTxAmount = (totalSupply() * percentBIPS) / 10000;
    }

    function updateCooldownPeriod(uint256 timeInHours) external onlyOwner {
        require (timeInHours >= 2 && timeInHours <= 24, "AWT: CooldownPeriod out of range");
        cooldownPeriod = timeInHours * 1 hours;
    }

    function canSend(address _address) external view returns (bool) {
        return isExemptFromTxLimit[_address] || block.timestamp >= lastHotTxTime[_address] + cooldownPeriod;
    }
}

contract Poken is AntiWhaleToken {

    uint256 initialSupply = 5000000000 * 10**9;

    constructor(address _charityWallet)
        ERC20("Poken", "PKN") 
        ReducingTaxToken(initialSupply, _charityWallet)
        AntiWhaleToken(
            (initialSupply * 50) / 10000,
            (initialSupply * 25) / 10000,
            3 hours)
    {
        _mint(owner(), initialSupply);
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }
}
