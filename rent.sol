//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract CAR {
    mapping (uint256 => uint256) public carBonus;
}

interface iCAR {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

contract PowerCarRental{

    address public car_address;

    event Sent(address indexed payee, uint256 amount);
    event Times(uint256 carOne, uint256 timeOne, uint256 carTwo, uint256 timeTwo);

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
    
    constructor(address _address){
        car_address = _address;
    }

     function _getCarBonus(uint256 tokenId) public view returns (uint256){
        CAR car = CAR(car_address);
        return car.carBonus(tokenId) * 5;
    }

    function _isOwner(uint256 tokenId) public view returns (address owner){
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

    function claimRacerBalance () public{
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
        require(carState[carOne] == State.Ready, "This CAR is in use.");
        require(msg.value <= 100e18, "Max amount 100 CLO");
        require(msg.value >= 1e18, "Min amount 1 CLO");
        dragRaces[carOne].raceBalance += msg.value;
        carStateSet(carOne);
        dragRaces[carOne].carOne = carOne;
        dragRaces[carOne].pilotOne = msg.sender;
    }
    
    function acceptDragRace(uint256 carOne, uint256 carTwo) payable public {
        require(fairPlay(carOne, carTwo), "Can not accept a race against a Car of a lower tier");
        require(carState[carTwo] == State.Ready, "This CAR is in use.");
        require(carState[carOne] == State.Set, "Your opponent is not ready to race");
        require(msg.value >= dragRaces[carOne].raceBalance, "The bet should be equal to your opponent's bet");
        dragRaces[carOne].raceBalance += msg.value;
        carStateSet(carTwo);
        dragRaces[carOne].carTwo = carTwo;
        dragRaces[carOne].pilotTwo = msg.sender;
        dragRace(carOne, carTwo);
    }
    
    function dragRace(uint256 carOne, uint256 carTwo) internal {
        
        carStateGo(carOne);
        carStateGo(carTwo);
        
        uint256 carOneTime;
        uint256 carTwoTime;

        uint256 pilotWinnerPrize = dragRaces[carOne].raceBalance - (dragRaces[carOne].raceBalance / 10);
        uint256 carOwnerPrize = dragRaces[carOne].raceBalance / 10;
        
        carOneTime = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, carOne)))%27; 
        carTwoTime = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, carTwo, carOneTime)))%27;
        
        //Apply carBonus
        carOneTime += _getCarBonus(carTwo);
        carTwoTime += _getCarBonus(carOne);
        
        if(carOneTime > carTwoTime){ //CarTwo Wins
            racerBalance[_isOwner(carTwo)] += carOwnerPrize;
            racerBalance[dragRaces[carOne].pilotTwo] += pilotWinnerPrize;
            carWinRate[carTwo].wins += 1;
        }

        if(carOneTime < carTwoTime){ //CarOne Wins
            racerBalance[_isOwner(carOne)] += carOwnerPrize;
            racerBalance[dragRaces[carOne].pilotOne] += pilotWinnerPrize;
            carWinRate[carOne].wins += 1;
        }

        if(carOneTime == carTwoTime){ //Tie
            racerBalance[dragRaces[carOne].pilotOne] += dragRaces[carOne].raceBalance/2;
            racerBalance[dragRaces[carOne].pilotTwo] += dragRaces[carOne].raceBalance/2;
        }
        
        carWinRate[carOne].total += 1;
        carWinRate[carTwo].total += 1;
        
        delete dragRaces[carOne];
        carStateReady(carOne);
        carStateReady(carTwo);
        
        emit Times(carOne, carOneTime, carTwo, carTwoTime);
    }
}
