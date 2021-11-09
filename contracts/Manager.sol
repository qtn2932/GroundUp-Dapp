// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "hardhat/console.sol";
import "./QEntry.sol";

contract Manager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for QEntry;
    using SafeMath for uint256;

    struct PrizePool {
        IERC20 prizeToken;
        uint256 countEntry;
        address currentWinner;
        uint256 poolId;
        uint256 prizeUnit;
        uint256 timeLastEntered;
    }

    PrizePool[] public poolCollection;
    address  public burnAddress = address(0x000000000000000000000000000000000000dEaD);
    QEntry public qentry;
    uint public minimumPool = 50*1e18;
    address public buyBackAddress = address(0x0);
    mapping(IERC20=>uint) public pendingBalance;
    mapping(uint => uint) public poolDurations;

    event PoolCreated(address indexed user, uint pid, IERC20 prizeToken, uint prizeUnit);
    event Entered(address indexed user, uint pid, uint finalAmount);
    event Claimed(address indexed user);
    event Donated(address indexed user, uint amount);

    constructor(){
    }
    function poolLength() external view returns(uint256){
        return poolCollection.length;
    }

    function setQEntry(QEntry _qentry) public onlyOwner{
        qentry = _qentry;
    }

    function setBuyBackAddress(address _buyBack) public onlyOwner{
        buyBackAddress = _buyBack;
    }

    //create prize pool if there is enough fund
    function createPool(IERC20 _prizeToken, uint256 _prizeUnit, uint256 _poolDuration) public nonReentrant {
        require(_prizeUnit>=minimumPool);
        require(_prizeToken.balanceOf(address(this)).sub(pendingBalance[_prizeToken]) >= _prizeUnit);
        poolCollection.push(PrizePool({
        prizeToken: _prizeToken,
        countEntry: 0,
        currentWinner: buyBackAddress,
        poolId: poolCollection.length,
        prizeUnit: _prizeUnit,
        timeLastEntered: block.timestamp.add(_poolDuration)
        }));
        pendingBalance[_prizeToken] = pendingBalance[_prizeToken].add(_prizeUnit);
        poolDurations[poolCollection.length] = _poolDuration;
        emit PoolCreated(msg.sender, poolCollection.length, _prizeToken, _prizeUnit);
    }

    function enter(uint256 _pid) public nonReentrant {
        uint256 fee = poolCollection[_pid].prizeUnit.div(100);
        require(qentry.balanceOf(msg.sender) >= fee, "balance: not enough balance");
        require(block.timestamp >= poolCollection[_pid].timeLastEntered, "early: pool has not opened");
        require(block.timestamp.sub(poolCollection[_pid].timeLastEntered) <= poolDurations[_pid], "timeout: pool closed");
        qentry.safeTransferFrom(msg.sender, burnAddress, fee);
        poolCollection[_pid].timeLastEntered = block.timestamp;
        poolCollection[_pid].countEntry = poolCollection[_pid].countEntry.add(1);
        poolCollection[_pid].currentWinner = msg.sender;
        emit Entered(msg.sender, _pid,poolCollection[_pid].countEntry );
    }

    //donate to prize pool
    function donate(IERC20 _donateToken, uint256 _amount) public {
        _donateToken.safeTransfer(address(this), _amount);
    }

    function claimPrice(uint256 _pid) public nonReentrant {
        require(block.timestamp.sub(poolCollection[_pid].timeLastEntered) > poolDurations[_pid]);
        require(qentry.balanceOf(msg.sender) >= poolCollection[_pid].countEntry.mul(1e18));
        qentry.safeTransferFrom(msg.sender,burnAddress, poolCollection[_pid].countEntry.mul(1e18));
        uint256 reward = poolCollection[_pid].prizeUnit.mul(80).div(100);
        uint256 buyBackFee = poolCollection[_pid].prizeUnit.sub(reward);
        poolCollection[_pid].prizeToken.transferFrom(address(this),poolCollection[_pid].currentWinner, reward);
        poolCollection[_pid].prizeToken.transferFrom(address(this),buyBackAddress, buyBackFee);
        emit Claimed(msg.sender);
    }

    function setPoolDuration(uint256 _duration, uint256 _pid) public onlyOwner {
        poolDurations[_pid] = _duration;
    }

}
