//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract CAR {
    mapping (uint256 => uint256) public carBonus;
}

interface iCAR {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

contract RaceForCLO is Ownable{

    address payable private withdrawalWallet;
    uint256 public feesBalance;
    uint256 public raceFee = 50000000000000000000;
    address public car_address;

    event Sent(address indexed payee, uint256 amount);

    //DragRace
    event RaceWinner(address winner, uint256 timeOne, uint256 timeTwo);

    enum State {Ready, Set, Go}
    mapping (uint256 => State) public carState;
    
    struct DragRace {
        uint256 carOne;
        address pilotOne;
        uint256 carTwo;
        address pilotTwo;
        uint256 raceBalance;
    }
    mapping (uint256 => DragRace) public dragRaces;

    struct WinRate {
        uint256 total;
        uint256 wins;
    }
    mapping (uint256 => WinRate) public carWinRate;

    //Amount of CLO a Racer has won and has not been claimed.
    mapping (address => uint256) public racerBalance;
    mapping (uint256 => uint256) public leaderBoard; //Amount of CLO a Car won.
    
    constructor(address _address){
        car_address = _address;
        withdrawalWallet = payable(_msgSender());
    }
   
    receive() external payable onlyOwner{}

    function _getCarBonus(uint256 tokenId) internal view returns (uint256){
        CAR car = CAR(car_address);
        return car.carBonus(tokenId);
    }

    function _isOwner(uint256 tokenId) internal view returns (address owner){
        iCAR icar = iCAR(car_address);
        return icar.ownerOf(tokenId);
    }

    function carStateReady(uint256 tokenId) internal{
        require(carState[tokenId] != State.Ready);
        carState[tokenId] = State.Ready;
    }
    
    function carStateSet(uint256 tokenId) internal{
        require(carState[tokenId] == State.Ready);
        carState[tokenId] = State.Set;
    }
    
    function carStateGo(uint256 tokenId) internal{
        require(carState[tokenId] == State.Set);
        carState[tokenId] = State.Go;
    }

    function claimRaceBalance () public{
            uint256 toPay = racerBalance[msg.sender];
            racerBalance[msg.sender] = 0;
            payable(msg.sender).transfer(toPay);
            emit Sent(msg.sender, toPay);
    }

    function fairPlay(uint256 carOne, uint256 carTwo) internal view returns(bool){
        uint256 carBonusOne = _getCarBonus(carOne);
        uint256 carBonusTwo = _getCarBonus(carTwo);
        if(carBonusOne % 2 == 0){
            if(carBonusOne+1 >= carBonusTwo){
                return true;
            }
        }else{
            if(carBonusOne >= carBonusTwo){
                return true;
            }
        }
        return false;
    }

    //DragRace
    function createDragRace(uint256 carOne) payable public {
        require(carState[carOne] == State.Ready, "This CAR is not able to RUN");
        require(_isOwner(carOne) == msg.sender, "CAR: caller is not owner");
        require(msg.value >= raceFee);
        feesBalance += raceFee;
        dragRaces[carOne].raceBalance += (msg.value - raceFee);
        carStateSet(carOne);
        dragRaces[carOne].carOne = carOne;
        dragRaces[carOne].pilotOne = msg.sender;
    }
    

    function acceptDragRace(uint256 carOne, uint256 carTwo) payable public {
        require(fairPlay(carOne, carTwo), "Can not accept a race against a Car of a lower tier");
        require(carState[carTwo] == State.Ready, "This CAR is not able to RUN");
        require(_isOwner(carTwo) == msg.sender, "CAR: caller is not owner");
        require(_isOwner(carOne) != msg.sender, "Can not compit against you");
        require(carState[carOne] == State.Set, "Your opponent is not ready to race");
        require(msg.value >= raceFee + dragRaces[carOne].raceBalance, "The bet should be equal to your opponenst bet");
        feesBalance += raceFee;
        dragRaces[carOne].raceBalance += (msg.value - raceFee);
        carStateSet(carTwo);
        dragRaces[carOne].carTwo = carTwo;
        dragRaces[carOne].pilotTwo = msg.sender;
        dragRace(carOne, carTwo);
    }

    function cancelDragRace(uint256 carOne) public {
        require(carState[carOne] == State.Set, "This CAR is not able to RUN");
        require(_isOwner(carOne) == msg.sender, "CAR: caller is not owner");
        carStateReady(carOne);
        racerBalance[msg.sender] += dragRaces[carOne].raceBalance;
        delete dragRaces[carOne];
    }

    
    function dragRace(uint256 carOne, uint256 carTwo) internal {
        
        carStateGo(carOne);
        carStateGo(carTwo);
        
        uint256 carOneTime;
        uint256 carTwoTime;
        address _winner;
        
        carOneTime = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, carOne)))%27; 
        carTwoTime = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, carTwo, carOneTime)))%27;
        
        //Apply carBonus
        carOneTime += _getCarBonus(carTwo) * 5;
        carTwoTime += _getCarBonus(carOne) * 5;
        
        if(carOneTime > carTwoTime){ //CarTwo Wins
            racerBalance[dragRaces[carOne].pilotTwo] += dragRaces[carOne].raceBalance;
            leaderBoard[carTwo] += dragRaces[carOne].raceBalance;
            _winner = dragRaces[carOne].pilotTwo;
            carWinRate[carTwo].wins += 1;
        }
        if(carOneTime < carTwoTime){ //CarTwo One
            racerBalance[dragRaces[carOne].pilotOne] += dragRaces[carOne].raceBalance;
            leaderBoard[carOne] += dragRaces[carOne].raceBalance;
            _winner = dragRaces[carOne].pilotOne;
            carWinRate[carOne].wins += 1;
        }

        //Tie.
        if(carOneTime == carTwoTime){ 
            racerBalance[dragRaces[carOne].pilotOne] += dragRaces[carOne].raceBalance/2;
            racerBalance[dragRaces[carOne].pilotTwo] += dragRaces[carOne].raceBalance/2;
        }
        
        carWinRate[carOne].total += 1;
        carWinRate[carTwo].total += 1;
        
        delete dragRaces[carOne];
        carStateReady(carOne);
        carStateReady(carTwo);
        
        emit RaceWinner(_winner, carOneTime, carTwoTime);
    }

    //carOwner Functions ^^^^^^

    function getCallistos() public onlyOwner{
        uint256 toPay = feesBalance;
        feesBalance = 0;
        withdrawalWallet.transfer(toPay);
        emit Sent(msg.sender, toPay);
    }

    function getBalance() public view returns(uint256 contractBalance){
        return address(this).balance;
    }
}
