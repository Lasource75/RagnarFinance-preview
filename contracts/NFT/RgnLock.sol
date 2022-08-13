// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./imports/CountersUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


import "../Tokens/RGN.sol";
import "./BRGN.sol";
import "./SvgStorage.sol";

import "./imports/RoyaltiesImpl.sol";
import "./imports/LibPart.sol";
import "./imports/LibRoyalties.sol";

/*
  _____                                ______ _
 |  __ \                              |  ____(_)
 | |__) |__ _  __ _ _ __   __ _ _ __  | |__   _ _ __   __ _ _ __   ___ ___
 |  _  // _` |/ _` | '_ \ / _` | '__| |  __| | | '_ \ / _` | '_ \ / __/ _ \
 | | \ \ (_| | (_| | | | | (_| | |    | |    | | | | | (_| | | | | (_|  __/
 |_|  \_\__,_|\__, |_| |_|\__,_|_|    |_|    |_|_| |_|\__,_|_| |_|\___\___|
               __/ |
              |___/
*/

contract RGNLOCK is
RoyaltiesImpl,
ERC721,
ReentrancyGuard,
Pausable,
ERC721Enumerable,
Ownable
{

    using CountersUpgradeable for CountersUpgradeable.Counter;

    struct RgnLockEntity {
        uint256 id;
        uint256 creationTime;
        uint256 lastProcessing;
        uint256 timeToLock;
        uint8 monthLock;
        uint256 rightsTime;
        uint256 rgnLock;
        uint256 bRgnLock;
        uint16 apr;
        address owner;
        bool exists;
    }

    mapping(uint256 => RgnLockEntity) public _rgnsLock;

    CountersUpgradeable.Counter private _rgnCounter;

    // Total RGN locked
    uint256 public totalValueLocked;

    // Total BRGN locked into nft
    uint256 public totalValueBrgnLocked;

    // The RGN TOKEN!
    RGN private rgn;

    // The BRGN TOKEN!
    BRGN private brgn;

    // The storageSVG
    storageSVG private svg;

    // Total RGN locked per month
    mapping (uint8 => uint256) public totalrgnLockByTiers;

    // Allocation RGN per month
    mapping (uint8 => uint256) public allocByTiers;

    // Counter Generate RGN per month
    mapping (uint8 => uint256) public generateRgnByTiers;

    // List of months for blocking
    uint8[] private timeLockMonth;

    // Percent total RGN supply locked by month
    uint8[] private percentTotalRgnSupplyByTiers;

    // List number BRGN generate per RGN
    uint64[] private generationBrgnPerRgn;

    // Time before next action
    uint public compoundDelay;

    // Time before voting rights
    uint public timeBeforeRights;

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    // RGN tokens created per second.
    uint256 public rgnPerSec;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    address payable royaltiesAddressPayable;

    // Royalties address for resale tax on marketplaces
    address public royaltiesAddress;


    constructor() ERC721("RgnLock", "RGNL"){
        compoundDelay = 86400; // 1 day
        timeBeforeRights = 432000; // 5 days

        rgnPerSec = 999990;
        require(rgnPerSec <= 10**6, "Emission too high");

        totalAllocPoint = 0;
        // Information about each month for the locking
        timeLockMonth = [1,3,6,12,18];

        percentTotalRgnSupplyByTiers = [30,30,20,10,10];
        generationBrgnPerRgn = [200000000000000000, 400000000000000000, 600000000000000000, 800000000000000000, 1000000000000000000];

        // royalties
        royaltiesAddressPayable = payable(0xd1c20fE83019b402f7Aa9663dB1F736f1F883645);
    }

    /// @notice create nft, amount blocked for a specified time
    /// @param _account user address
    /// @param _amountLock amount RGN lock
    /// @param _timeToLock month number
    function mint(address _account, uint256 _amountLock, uint8 _timeToLock)
    external
    callerIsUser
    checkTimeLock(_timeToLock)
    {
        address sender = _msgSender();
        require(_amountLock <= rgn.balanceOf(sender), "Balance $RGN to low");
        require(possibleCheck(_amountLock, _timeToLock), "Sorry impossible create more nft");

        // burn token creation rgnLock
        rgn.burn(sender, _amountLock);

        // Increment total $rgn lock
        totalValueLocked += _amountLock;

        _rgnCounter.increment();
        uint256 newRgnId = _rgnCounter.current();

        addTotalrgnLockByTiers(_timeToLock, _amountLock);
        // Create RgnLockEntity to mapping
        _rgnsLock[newRgnId] = RgnLockEntity({
        id: _rgnCounter.current(),
        creationTime: currentTime(),
        timeToLock: currentTime() + timeLock(_timeToLock),
        lastProcessing: currentTime(),
        monthLock: _timeToLock,
        rightsTime: currentTime() + timeBeforeRights,
        owner: _account,
        rgnLock: _amountLock,
        bRgnLock: 0,
        apr : 0,
        exists: true
        });

        //generate rgnLock nft
        _safeMint(_account, newRgnId);
        setRoyalties(newRgnId, 500);

        emit Create(_account, newRgnId, _amountLock);
    }

    /// @notice withdraw amount RGN in nft, beware deletion of brgn
    /// @param _rgnLockId Number of token
    function withdraw(uint256 _rgnLockId)
    external
    nonReentrant
    onlyNftOwner
    checkPermissions(_rgnLockId)
    whenNotPaused
    {
        RgnLockEntity storage rgnLock = _rgnsLock[_rgnLockId];
        require(rgnLock.exists, "Rgn lock not exist");
        require(isProcessable(rgnLock), "Sorry delay is not passed");
        require(currentTime() > rgnLock.timeToLock , "Impossible withdraw before time to unlock");
        compoundReward(_rgnLockId,true);
        rgn.mint(rgnLock.owner, rgnLock.rgnLock);

        brgn.burn(address(this), rgnLock.bRgnLock);
        _burn(_rgnLockId);
        emit Withdraw(rgnLock.owner, _rgnLockId, rgnLock.rgnLock);
        totalValueLocked -= rgnLock.rgnLock;
        totalValueBrgnLocked -= rgnLock.bRgnLock;
        rgnLock.rgnLock = 0;
        rgnLock.bRgnLock = 0;
        rgnLock.rightsTime = 0;
        rgnLock.exists = false;
        rgnLock.lastProcessing = currentTime();
        removeTotalrgnLockByTiers(rgnLock.monthLock, rgnLock.rgnLock);
    }

    /// @notice Generate BRGN
    /// @param _rgnLockId Number of token
    function generateBRgn(uint256 _rgnLockId)
    external
    nonReentrant
    onlyNftOwner
    checkPermissions(_rgnLockId)
    whenNotPaused
    {
        RgnLockEntity storage rgnLock = _rgnsLock[_rgnLockId];
        require(rgnLock.exists, "Rgn lock not exist");
        require(isProcessable(rgnLock), "Sorry delay is not passed");
        uint256 rewards = calculateRewardsBrgn(rgnLock);
        brgn.mint(address(this), rewards);
        emit GenerateBrgn(rgnLock.owner, _rgnLockId, rgnLock.rgnLock);
        rgnLock.bRgnLock += rewards;
        rgnLock.lastProcessing = currentTime();
        totalValueBrgnLocked += rewards;
    }

    /// @notice compound reward
    /// @param _rgnLockId Number of token
    /// @param inside differentiate mint and compound
    function compoundReward(uint256 _rgnLockId, bool inside)
    public
    checkPermissions(_rgnLockId)
    whenNotPaused
    {
        uint256 amountToCompound = _getTokenCompoundRewards(_rgnLockId, inside);
        require(amountToCompound > 0, "You must wait until you can compound again");

        emit Compound(_msgSender(), _rgnLockId, amountToCompound);
    }

    /// @notice Give possibility adding RGN to nft
    /// @param _rgnLockId Number of token
    /// @param _amountToken amount RGN add in nft
    function addTokenLock(uint256 _rgnLockId, uint256 _amountToken)
    public

    checkPermissions(_rgnLockId)
    whenNotPaused
    {
        require(_amountToken > 0, "RGN funds insufficient");
        RgnLockEntity storage rgnLock = _rgnsLock[_rgnLockId];
        require(isProcessable(rgnLock), "Sorry delay is not passed");
        address sender = _msgSender();
        rgn.burn(sender, _amountToken);
        rgnLock.rgnLock += _amountToken;
        rgnLock.lastProcessing = currentTime();
        addTotalrgnLockByTiers(rgnLock.monthLock, _amountToken);
        emit AddToken(sender, rgnLock.id, _amountToken);

    }

    /// @notice View function to see pending tokens on frontend.
    /// @param _tokenId Number of token
    function pendingTokens(uint256 _tokenId)
    external
    view
    returns (
        uint256 pendingRGN,
        uint256 pendingBRGN
    ) {
        RgnLockEntity storage rgnLock = _rgnsLock[_tokenId];

        pendingRGN = calculateRewardsRgn(rgnLock);
        pendingBRGN = calculateRewardsBrgn(rgnLock);
    }

    /// @notice mint RGN function or compound
    /// @param  _rgnLockId Number of token
    /// @param inside differentiate mint and compound
    function _getTokenCompoundRewards(uint256 _rgnLockId, bool inside)
    private
    returns (uint256)
    {
        RgnLockEntity storage rgnLock = _rgnsLock[_rgnLockId];

        if (!isProcessable(rgnLock))
            return 0;

        uint256 rewards = calculateRewardsRgn(rgnLock);
        generateRgnByTiers[rgnLock.monthLock] = rewards;

        if (rewards > 0) {
            rgnLock.lastProcessing = currentTime();
            // if the user wants to recover the rewards on his wallet
            if (!inside) {
                rgn.mint(rgnLock.owner, rewards);
            }
            // prefer compound directly in the rgnLock
            else {
                totalValueLocked += rewards;
                rgnLock.rgnLock += rewards;
                addTotalrgnLockByTiers(rgnLock.monthLock, rewards);
            }
        }
        return rewards;
    }

    function nftsOwnedBy(address _owner) public view returns (uint16){
        uint16 count = 0;
        for(uint i = 0; i <= _rgnCounter.current(); i++){
            if(_rgnsLock[i].owner == _owner){
                count++;
            }
        }
        return count;
    }

    function getNftsOfOwner(address _owner) public view returns (uint32[] memory){
        uint len = _rgnCounter.current();
        uint numberOfNfts = nftsOwnedBy(_owner);
        uint32 [] memory ownedNft = new uint32[](numberOfNfts);
        uint cpt = 0;
        for(uint256 i = 0; i <= len; i++){
            if(_rgnsLock[i].owner == _owner){
                ownedNft[cpt] = uint32(i);
                cpt++;
            }
        }
        return ownedNft;
    }

    function isProcessable(RgnLockEntity memory rgnLock)
    private
    view
    returns (bool)
    {
        return
        currentTime() >= rgnLock.lastProcessing + compoundDelay;
    }

    /// @notice Check if value matches
    /// @param value month number
    function _isPresentMonth(uint value)
    internal
    view
    returns (uint8 position)
    {
        for(uint8 i=0; i < timeLockMonth.length; i++) {
            if (timeLockMonth[i] == value) {
                return i;
            }
        }
        return 100;
    }

    /// @notice Give information calculation rewards RGN
    /// @param rgnLock entity connect to nft
    function calculateRewardsRgn(RgnLockEntity memory rgnLock)
    private
    view
    returns (uint256)
    {
        uint256 rewards = 0;
        if (currentTime() > rgnLock.lastProcessing) {
            uint256 multiplier = currentTime() - rgnLock.lastProcessing;
            uint256 rgnReward = (multiplier * rgnPerSec * allocByTiers[rgnLock.monthLock])
            / totalAllocPoint;
            uint256 accRGNPerShare = generateRgnByTiers[rgnLock.monthLock] + (rgnReward)
            / totalValueLocked;
            rewards = (rgnLock.rgnLock * accRGNPerShare) / 1e12;
        }
        return rewards;
    }

    /// @notice Give information calculation rewards BRGN
    /// @param rgnLock entity connect to nft
    function calculateRewardsBrgn(RgnLockEntity memory rgnLock)
    public view
    returns (uint256)
    {
        uint256 rewards = 0;
        uint maxGeneration = generationBrgnPerRgn[_isPresentMonth(rgnLock.monthLock)] * (rgnLock.rgnLock / 10 **18);
        uint tiersTimeLock = (timeLock(rgnLock.monthLock) * 30) / 100;
        require(rgnLock.bRgnLock < maxGeneration, "Max generate brgn");
        uint256 brgnPerSec = (maxGeneration / tiersTimeLock);
        if (currentTime() > rgnLock.lastProcessing) {
            uint256 multiplier = currentTime() - rgnLock.lastProcessing;
            rewards = (multiplier * brgnPerSec);
        }
        if (rewards + rgnLock.bRgnLock > maxGeneration) {
            rewards = maxGeneration - rgnLock.bRgnLock;
        }

        return rewards;
    }

    function addTotalrgnLockByTiers(uint8 _pid, uint _amount)
    private
    {
        totalrgnLockByTiers[_pid] += _amount;
    }

    function removeTotalrgnLockByTiers(uint8 _pid, uint _amount)
    private
    {
        totalrgnLockByTiers[_pid] -= _amount;
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    modifier checkPermissions(uint256 _rgnLockId) {
        _checkPermissions(_rgnLockId);
        _;
    }

    function _checkPermissions(uint256 _rgnLockId) private view {
        address sender = _msgSender();
        require(nftExists(_rgnLockId), "This nft doesn't exist");
        require(
            isApprovedOrOwnerOfNft(sender, _rgnLockId),
            "Not an owner"
        );
    }

    modifier checkTimeLock(uint8 _monthLock) {
        require(timeLock(_monthLock) != 0, "Sorry unknown month lock");
        _;
    }

    modifier onlyNftOwner() {
        _onlyNftOwner();
        _;
    }

    function _onlyNftOwner() private view {
        address sender = _msgSender();
        require(
            sender != address(0),
            "Cannot be from the zero address"
        );
        require(balanceOf(sender) > 0,
            "No Nft owned by this account"
        );
    }

    // Events
    event Create(
        address indexed account,
        uint256 indexed newTrsrNodeId,
        uint256 amount
    );

    event AddToken(
        address indexed account,
        uint256 indexed trsrNodeId,
        uint256 indexed amountAdd
    );

    event Withdraw(
        address indexed account,
        uint256 indexed trsrnodeId,
        uint256 amoutLock
    );

    event GenerateBrgn(
        address indexed account,
        uint256 indexed trsrnodeId,
        uint256 amoutLock
    );

    event Compound(
        address indexed account,
        uint256 indexed nftId,
        uint256 amountToCompound
    );

    // Functions OnlyOwner
    function setToken(RGN _rgn) public onlyOwner {
        rgn = _rgn;
    }

    function setBToken(BRGN _brgn) public onlyOwner {
        brgn = _brgn;
    }

    function setSvg(storageSVG _svg) public onlyOwner {
        svg = _svg;
    }

    function setTimeBeforeRights (uint256 _time)
    public
    onlyOwner
    {
        timeBeforeRights = _time;
    }

    function setTimeLockMonth(uint8[] memory _timeLock)
    public
    onlyOwner
    {
        timeLockMonth = _timeLock;
    }

    function setAllocByTiers(uint8 _month, uint256 _alloc)
    public
    onlyOwner
    {
        allocByTiers[_month] = _alloc;
        totalAllocPoint += _alloc;
    }

    function setBrgnPerRgn(uint64 value, uint256 pid)
    public
    onlyOwner
    {
        generationBrgnPerRgn[pid] = value;
    }

    function setPercentTotalRgnSupplyByTiers(uint8 value, uint256 pid)
    public
    onlyOwner {
        percentTotalRgnSupplyByTiers[pid] = value;
    }

    // Views
    function currentTime()
    internal
    view returns(uint)
    {
        return block.timestamp;
    }

    function rightToVote(uint256 _rgnLockId)
    public
    view
    returns (bool)
    {
        RgnLockEntity memory rgnLock = _rgnsLock[_rgnLockId];
        if (rgnLock.rightsTime <= currentTime())
            return true;
        else
            return false;
    }

    function isApprovedOrOwnerOfNft(address account, uint256 _rgnLockId)
    public
    view
    returns (bool)
    {
        return _isApprovedOrOwner(account, _rgnLockId);
    }

    function tokenURI(uint _rgnLockId)override(ERC721)
    public
    view
    returns (string memory)
    {
        RgnLockEntity memory rgnLock = _rgnsLock[_rgnLockId];
        return svg.tokenURI(rgnLock.exists, rgnLock.rgnLock, rgnLock.timeToLock, rgnLock.bRgnLock, rgnLock.monthLock, rgnLock.id);
    }

    function nftExists(uint256 _rgnLockId) private view returns (bool) {
        require(_rgnLockId > 0, "Id must be higher than zero");
        RgnLockEntity memory rgnLock = _rgnsLock[_rgnLockId];
        if (rgnLock.exists) {
            return true;
        }
        return false;
    }

    function timeLock(uint8 _monthLock) private pure returns (uint256) {
        if (_monthLock == 18)
            return 47336400; // 18 months
        else if (_monthLock == 12)
            return 31557600; // 12 months
        else if (_monthLock == 6)
            return 15778800; // 6 months
        else if (_monthLock == 3)
            return 7889400; // 3 months
        else if (_monthLock == 1)
            return 2629800; // 1 months
        else
            return 0;
    }

    function possibleCheck(uint256 _amountLock, uint8 _monthLock) internal view returns (bool) {
        require(_amountLock != 0, "$RGN is 0");

        uint8 positionTab = _isPresentMonth(_monthLock);
        uint amountAuthorizedByTiers = rgn.totalSupply() * percentTotalRgnSupplyByTiers[positionTab] / 100;

        if ( totalrgnLockByTiers[positionTab] + _amountLock < amountAuthorizedByTiers)
            return true;
        else
            return  false;
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721, ERC721Enumerable)
    returns (bool)
    {
        if (interfaceId == LibRoyalties._INTERFACE_ID_ROYALTIES || interfaceId == _INTERFACE_ID_ERC2981) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    // Mandatory overrides
    function _burn(uint256 _rgnLockId)
    internal
    override(ERC721)
    {
        RgnLockEntity storage rgnLock = _rgnsLock[_rgnLockId];
        rgnLock.exists = false;
        ERC721._burn(_rgnLockId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    )
    internal
    virtual
    override(ERC721, ERC721Enumerable)
    whenNotPaused
    {
        RgnLockEntity storage rgnLock = _rgnsLock[amount];
        rgnLock.owner = to;
        super._beforeTokenTransfer(from, to, amount);

    }

    function setRoyalties(uint tokenId, uint96 percentageBasisPoints)
    internal
    {
        LibPart.Part[] memory royalties = new LibPart.Part[](1);
        royalties[0].value = percentageBasisPoints;
        royalties[0].account = royaltiesAddressPayable;
        _saveRoyalties(tokenId, royalties);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
    external
    view
    returns (address receiver, uint256 royaltyAmount)
    {
        LibPart.Part[] memory _royalties = royalties[_tokenId];
        if (_royalties.length > 0) {
            return (_royalties[0].account, (_salePrice * _royalties[0].value) / 10000);
        }
    }
}
