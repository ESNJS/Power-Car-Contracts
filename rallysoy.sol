// SPDX-License-Identifier: GPL

pragma solidity ^0.8.0;

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(msg.sender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

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

library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * This test is non-exhaustive, and there may be false-negatives: during the
     * execution of a contract's constructor, its address will be reported as
     * not containing a contract.
     *
     * > It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }
}

interface INFT {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function standard() external view returns (string memory);
    function balanceOf(address _who) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function transfer(address _to, uint256 _tokenId, bytes calldata _data) external returns (bool);
    function silentTransfer(address _to, uint256 _tokenId) external returns (bool);
    
    function priceOf(uint256 _tokenId) external view returns (uint256);
    function bidOf(uint256 _tokenId) external view returns (uint256 price, address payable bidder, uint256 timestamp);
    
    function setBid(uint256 _tokenId, uint256 _amountInWEI) payable external returns (bool);
    function withdrawBid(uint256 _tokenId) external returns (bool);
}

abstract contract NFTReceiver {
    function nftReceived(address _from, uint256 _tokenId, bytes calldata _data) external virtual;
}

contract RallySoy is INFT, Ownable{
    
    using Address for address;

    //Rally Events
    event Sent(address indexed payee, uint256 amount);
    event RaceWinner(address winner, uint256 timeOne, uint256 timeTwo);

    //NFT Events
    event Transfer     (address indexed from, address indexed to, uint256 indexed tokenId);
    event TransferData (bytes data);

    //Rally Variables
    uint256 public start; //When the season starts.
    uint256 public end; //When the season ends.
    uint256 public seasonJackpot;
    uint256 public ticketBalance;                       //Balance from ticket sales
    uint256 public ticketPrice;  //Amount paid for racing (in WEI)
    address public car_address;
    uint256 public season;
    uint256 public rallyTotalEarnings;
    enum State {Ready, Set, Go}
    mapping (uint256 => State) public carState;

    struct Rally {
        uint256 carOne;
        uint256 carTwo;
        uint256 raceBalance;
    }

    struct SeasonWinners {
        uint256 first;
        uint256 second;
        uint256 third;
        uint256 seasonBalance;
        bool seasonStarted;
        mapping (uint256 => uint256) seasonPoints; //Winner: 2points. Tie: 1points.
    }

    mapping (uint256 => Rally) public rallies;
    mapping (uint256 => uint256) public bonusMultiplier;
    mapping (uint256 => SeasonWinners) public seasonHistory; 
    mapping (address => uint256) public racerBalance;

    //NFT Variables
    string public tokenImage;
    mapping (uint32 => Fee)         public feeLevels; // level # => (fee receiver, fee percentage)
    
    uint256 public bidLock = 1 days; // Time required for a bid to become withdrawable.
    
    struct Bid {
        address payable bidder;
        uint256 amountInWEI;
        uint256 timestamp;
    }
    
    struct Fee {
        address payable feeReceiver;
        uint256 feePercentage; // Will be divided by 100000 during calculations
    }                          // feePercentage of 100 means 0.1% fee
                               // feePercentage of 2500 means 2.5% fee

    
    mapping (uint256 => uint256) private _asks; // tokenID => price of this token (in WEI)
    mapping (uint256 => Bid)     private _bids; // tokenID => price of this token (in WEI)
    mapping (uint256 => uint32)  private _tokenFeeLevels; // tokenID => level ID / 0 by default

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_, uint256 _defaultFee, address _CARaddress, string memory _tokenImage) {
        _name   = name_;
        _symbol = symbol_;
        feeLevels[0].feeReceiver   = payable(msg.sender);
        feeLevels[0].feePercentage = _defaultFee;

        car_address = _CARaddress;
        ticketPrice = 50000000000000000000;

        _beforeTokenTransfer(address(0), msg.sender, 0);
        _balances[msg.sender] += 1;
        _owners[0] = msg.sender;
        tokenImage = _tokenImage;
        emit Transfer(address(0), msg.sender, 0);

        //falta el link a la imagen.
    }

    receive() external payable onlyOwner{}

    modifier checkTrade(uint256 _tokenId)
    {
        _;
        (uint256 _bid, address payable _bidder,) = bidOf(_tokenId);
        if(priceOf(_tokenId) > 0 && priceOf(_tokenId) <= _bid)
        {
            uint256 _reward = _bid - _claimFee(_bid, _tokenId);
            payable(ownerOf(_tokenId)).transfer(_reward);
            delete _bids[_tokenId];
            delete _asks[_tokenId];
            _transfer(ownerOf(_tokenId), _bidder, _tokenId);
            if(address(_bidder).isContract())
            {
                NFTReceiver(_bidder).nftReceived(ownerOf(_tokenId), _tokenId, hex"000000");
            }
        }
    }
    
    function standard() public view virtual override returns (string memory)
    {
        return "NFT RALLY SOY";
    }
    
    function priceOf(uint256 _tokenId) public view virtual override returns (uint256)
    {
        address owner = _owners[_tokenId];
        require(owner != address(0), "NFT: owner query for nonexistent token");
        return _asks[_tokenId];
    }
    
    function bidOf(uint256 _tokenId) public view virtual override returns (uint256 price, address payable bidder, uint256 timestamp)
    {
        address owner = _owners[_tokenId];
        require(owner != address(0), "NFT: owner query for nonexistent token");
        return (_bids[_tokenId].amountInWEI, _bids[_tokenId].bidder, _bids[_tokenId].timestamp);
    }
    
    function getTokenImage() public view virtual returns (string memory)
    {
        return tokenImage;
    }
    
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "NFT: balance query for the zero address");
        return _balances[owner];
    }
    
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "NFT: owner query for nonexistent token");
        return owner;
    }
    
    function setPrice(uint256 _tokenId, uint256 _amountInWEI) checkTrade(_tokenId) public returns (bool)
    {
        require(ownerOf(_tokenId) == msg.sender, "Setting asks is only allowed for owned NFTs!");
        _asks[_tokenId] = _amountInWEI;
        return true;
    }
    
    function setBid(uint256 _tokenId, uint256 _amountInWEI) payable checkTrade(_tokenId) public virtual override returns (bool)
    {
        (uint256 _previousBid, address payable _previousBidder, ) = bidOf(_tokenId);
        require(msg.value == _amountInWEI, "Wrong payment value provided");
        require(msg.value > _previousBid, "New bid must exceed the existing one");
        
        // Return previous bid if the current one exceeds it.
        if(_previousBid != 0)
        {
            _previousBidder.transfer(_previousBid);
        }
        _bids[_tokenId].amountInWEI = _amountInWEI;
        _bids[_tokenId].bidder      = payable(msg.sender);
        _bids[_tokenId].timestamp   = block.timestamp;
        return true;
    }
    
    function withdrawBid(uint256 _tokenId) public virtual override returns (bool)
    {
        (uint256 _bid, address payable _bidder, uint256 _timestamp) = bidOf(_tokenId);
        require(msg.sender == _bidder, "Can not withdraw someone elses bid");
        require(block.timestamp > _timestamp + bidLock, "Bid is time-locked");
        
        _bidder.transfer(_bid);
        delete _bids[_tokenId];
        return true;
    }
    
    function name() public view virtual override returns (string memory) {
        return _name;
    }
    
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }
    
    function transfer(address _to, uint256 _tokenId, bytes calldata _data) public override returns (bool)
    {
        _transfer(msg.sender, _to, _tokenId);
        if(_to.isContract())
        {
            NFTReceiver(_to).nftReceived(msg.sender, _tokenId, _data);
        }
        emit TransferData(_data);
        return true;
    }
    
    function silentTransfer(address _to, uint256 _tokenId) public override returns (bool)
    {
        _transfer(msg.sender, _to, _tokenId);
        return true;
    }
    
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }
    
    function _claimFee(uint256 _amountFrom, uint256 _tokenId) internal returns (uint256)
    {
        uint32 _level          = _tokenFeeLevels[_tokenId];
        address _feeReceiver   = feeLevels[_level].feeReceiver;
        uint256 _feePercentage = feeLevels[_level].feePercentage;
        
        uint256 _feeAmount = _amountFrom * _feePercentage / 100000;
        payable(_feeReceiver).transfer(_feeAmount);
        return _feeAmount;        
    }
    
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(RallySoy.ownerOf(tokenId) == from, "NFT: transfer of token that is not own");
        require(to != address(0), "NFT: transfer to the zero address");
        
        _asks[tokenId] = 0; // Zero out price on transfer
        
        // When a user transfers the NFT to another user
        // it does not automatically mean that the new owner
        // would like to sell this NFT at a price
        // specified by the previous owner.
        
        // However bids persist regardless of token transfers
        // because we assume that the bidder still wants to buy the NFT
        // no matter from whom.

        _beforeTokenTransfer(from, to, tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    //Custom Code
    function setFeeReceiver (address _address) public onlyOwner {
        feeLevels[0].feeReceiver   = payable(_address);
    }

    function setBonusMultiplier (uint256 tokenId, uint256 _bonusMultiplier) public onlyOwner {
        bonusMultiplier[tokenId] = _bonusMultiplier;
    }

    function _getCarBonus(uint256 tokenId) internal view returns (uint256){
        CAR car = CAR(car_address);
        return car.carBonus(tokenId);
    }

    function carOwner(uint256 tokenId) internal view returns (address owner){
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

    function createRally(uint256 carOne) payable public {
        require(carState[carOne] == State.Ready, "This CAR is not able to RUN");
        require(carOwner(carOne) == msg.sender, "CAR: caller is not owner");
        require(msg.value >= ticketPrice);
        rallyTotalEarnings += ticketPrice;
        if(seasonHistory[season].seasonStarted){
            seasonHistory[season].seasonBalance += ticketPrice/10;
            ticketBalance += ticketPrice - ticketPrice/10;
        }else{
            ticketBalance += ticketPrice - ticketPrice;
        }

        rallies[carOne].raceBalance += (msg.value - ticketPrice);
        carStateSet(carOne);
        rallies[carOne].carOne = carOne;
    }

    function acceptRally(uint256 carOne, uint256 carTwo) payable public {
        require(carState[carTwo] == State.Ready, "This CAR is not able to RUN");
        require(carOwner(carOne) == msg.sender, "CAR: caller is not owner");
        require(carOwner(carOne) != msg.sender, "Can not compit against you");
        require(carState[carOne] == State.Set, "Your opponent is not ready to race");
        require(msg.value >= ticketPrice + rallies[carOne].raceBalance, "The bet should be equal to your opponenst bet");
        rallyTotalEarnings += ticketPrice;
        if(seasonHistory[season].seasonStarted){
            seasonHistory[season].seasonBalance += ticketPrice/10;
            ticketBalance += ticketPrice - ticketPrice/10;
        }else{
            ticketBalance += ticketPrice - ticketPrice;
        }
        rallies[carOne].raceBalance += (msg.value - ticketPrice);
        carStateSet(carTwo);
        rallies[carOne].carTwo = carTwo;
        startRally(carOne);
    }

    function cancelRally(uint256 carOne) public {
        require(carState[carOne] == State.Set, "This CAR is not able to RUN");
        require(carOwner(carOne) == msg.sender, "CAR: caller is not owner");
        carStateReady(carOne);
        racerBalance[msg.sender] += rallies[carOne].raceBalance;
        delete rallies[carOne];
    }

    function startRally (uint256 raceID) internal {

        uint256 _carOne = rallies[raceID].carOne;
        uint256 _carTwo = rallies[raceID].carTwo;   
        uint256 carOneTime;
        uint256 carTwoTime;
        address _winner;

        carStateGo(_carOne);
        carStateGo(_carTwo);

        carOneTime   = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, _carTwo)))%51; 
        carTwoTime   = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, _carOne)))%51;

        //Apply carBonus
        carOneTime   += _getCarBonus(_carOne) * bonusMultiplier[_carOne];
        carTwoTime   += _getCarBonus(_carTwo) * bonusMultiplier[_carTwo];

        if(carOneTime > carTwoTime){ //CarTwo Wins
            racerBalance[carOwner(_carTwo)] += rallies[raceID].raceBalance;
            _winner = carOwner(_carTwo);
            seasonHistory[season].seasonPoints[_carTwo] += 2;
            sortWinner(_carTwo);
        }
        if(carOneTime < carTwoTime){ //CarTwo One
            racerBalance[carOwner(_carOne)] += rallies[raceID].raceBalance;
            _winner = carOwner(_carOne);
            seasonHistory[season].seasonPoints[_carOne] += 2;
            sortWinner(_carOne);
        }

        //Tie.
        if(carOneTime == carTwoTime){ 
            racerBalance[carOwner(_carOne)] += rallies[raceID].raceBalance/2;
            racerBalance[carOwner(_carTwo)] += rallies[raceID].raceBalance/2;
            seasonHistory[season].seasonPoints[_carOne] += 1;
            seasonHistory[season].seasonPoints[_carTwo] += 1;
            sortWinner(_carOne);
            sortWinner(_carTwo);
        }
        
       
        delete rallies[raceID];
        carStateReady(_carOne);
        carStateReady(_carTwo);
        
        emit RaceWinner(_winner, carOneTime, carTwoTime);
    }

    function getCallistos() public{
        uint256 toPay = ticketBalance;
        ticketBalance = 0;
        payable(ownerOf(0)).transfer(toPay);
        emit Sent(ownerOf(0), toPay);
    }

    //seasonPoints  

    function setTicketPrice (uint256 _amoutInWEI) internal {
        require(ownerOf(0) == msg.sender, "You are not the Rally Owner"); 
        require(_amoutInWEI >= 50000000000000000000 && _amoutInWEI <= 100000000000000000000, "Price goes from 50 to 100");
        ticketPrice = _amoutInWEI; //50000000000000000000
    }

    function actualBlock() public view returns (uint256 block_number){
        return block_number = block.number;
    }



    function sortWinner(uint256 car) internal {
        if(seasonHistory[season].seasonPoints[car] > seasonHistory[season].seasonPoints[seasonHistory[season].third]){
            seasonHistory[season].third = car;
            if(seasonHistory[season].seasonPoints[car] > seasonHistory[season].seasonPoints[seasonHistory[season].second]){
                seasonHistory[season].third = seasonHistory[season].second;
                seasonHistory[season].second = car;
                if(seasonHistory[season].seasonPoints[car] > seasonHistory[season].seasonPoints[seasonHistory[season].first]){
                    seasonHistory[season].second = seasonHistory[season].first;
                    seasonHistory[season].first = car;
                }
            }
        }
    }

    function startSeason(uint256 _amoutInWEI) public{
        require(ownerOf(0) == msg.sender, "You are not the Rally Owner"); 
        require(block.timestamp > end);
        end = block.timestamp + 7 days;
        setTicketPrice(_amoutInWEI);
    }

    function endSeason() public{
        require(ownerOf(0) == msg.sender, "You are not the Rally Owner"); 
        require(block.timestamp > end);

        racerBalance[carOwner(seasonHistory[season].first)] += seasonHistory[season].seasonBalance/2;
        racerBalance[carOwner(seasonHistory[season].second)] += seasonHistory[season].seasonBalance/4;
        racerBalance[carOwner(seasonHistory[season].third)] += seasonHistory[season].seasonBalance/4;
        season ++;
    }



}
