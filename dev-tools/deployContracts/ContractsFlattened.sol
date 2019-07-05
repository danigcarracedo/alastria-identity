
// File: contracts/libs/Eidas.sol

pragma solidity 0.4.23;

library Eidas {

    enum EidasLevel { Null, Reputational, Low, Substantial, High }

    /*function onlyReputational(EidasLevel _eidasLevel) returns (bool) {
        return (_eidasLevel == EidasLevel.Reputational);
    }

    function onlyLow(EidasLevel _eidasLevel) returns (bool) {
        return (_eidasLevel == EidasLevel.Low);
    }

    function onlySubstantial(EidasLevel _eidasLevel) returns (bool) {
        return (_eidasLevel == EidasLevel.Substantial);
    }

    function onlyHigh(EidasLevel _eidasLevel) returns (bool) {
        return (_eidasLevel == EidasLevel.High);
    }*/

    function atLeastLow(EidasLevel _eidasLevel) public pure returns (bool) {
        return atLeast(_eidasLevel, EidasLevel.Low);
    }

    /*function alLeastSubstantial(EidasLevel _eidasLevel) returns (bool) {
        return atLeast(_eidasLevel, EidasLevel.Substantial);
    }

    function alLeastHigh(EidasLevel _eidasLevel) returns (bool) {
        return atLeast(_eidasLevel, EidasLevel.High);
    }*/

    function atLeast(EidasLevel _eidasLevel, EidasLevel _level) public pure returns (bool) {
        return (uint(_eidasLevel) >= uint(_level));
    }

    /*function notNull(EidasLevel _eidasLevel) returns (bool) {
        return _eidasLevel != EidasLevel.Null;
    }

    function toEidasLevel(uint _level) returns (EidasLevel) {
        return EidasLevel(_level);
    }*/

}

// File: contracts/identityManager/AlastriaIdentityServiceProvider.sol

pragma solidity 0.4.23;


contract AlastriaIdentityServiceProvider {

    using Eidas for Eidas.EidasLevel;

    mapping(address => bool) internal providers;

    modifier onlyIdentityServiceProvider(address _identityServiceProvider) {
        require (isIdentityServiceProvider(_identityServiceProvider));
        _;
    }

    modifier notIdentityServiceProvider(address _identityServiceProvider) {
        require (!isIdentityServiceProvider(_identityServiceProvider));
        _;
    }

    constructor () public {
        // FIXME: This must be an Alastria_ID created from AlastriaIdentityManager.
        addIdentityServiceProvider(msg.sender);
    }

    function addIdentityServiceProvider(address _identityServiceProvider) public notIdentityServiceProvider(_identityServiceProvider) {
        providers[_identityServiceProvider] = true;
    }

    function deleteIdentityServiceProvider(address _identityServiceProvider) public onlyIdentityServiceProvider(_identityServiceProvider) {
        providers[_identityServiceProvider] = false;
    }

    function isIdentityServiceProvider(address _identityServiceProvider) public constant returns (bool) {
        return providers[_identityServiceProvider];
    }

}

// File: contracts/identityManager/AlastriaIdentityIssuer.sol

pragma solidity 0.4.23;


contract AlastriaIdentityIssuer {

    using Eidas for Eidas.EidasLevel;

    struct IdentityIssuer {
        Eidas.EidasLevel level;
        bool active;
    }

    mapping(address => IdentityIssuer) internal issuers;

    modifier onlyIdentityIssuer(address _identityIssuer) {
        require (issuers[_identityIssuer].active);
        _;
    }

    modifier notIdentityIssuer(address _identityIssuer) {
        require (!issuers[_identityIssuer].active);
        _;
    }

    modifier alLeastLow(Eidas.EidasLevel _level) {
        require (_level.atLeastLow());
        _;
    }

    constructor () public {
        // FIXME: This must be an Alastria_ID created from AlastriaIdentityManager.
        addIdentityIssuer(msg.sender, Eidas.EidasLevel.High);
    }

    function addIdentityIssuer(address _identityIssuer, Eidas.EidasLevel _level) public alLeastLow(_level) notIdentityIssuer(_identityIssuer) {
        IdentityIssuer storage identityIssuer = issuers[_identityIssuer];
        identityIssuer.level = _level;
        identityIssuer.active = true;

    }

    function updateIdentityIssuerEidasLevel(address _identityIssuer, Eidas.EidasLevel _level) public alLeastLow(_level) onlyIdentityIssuer(_identityIssuer) {
        IdentityIssuer storage identityIssuer = issuers[_identityIssuer];
        identityIssuer.level = _level;
    }

    function deleteIdentityIssuer(address _identityIssuer) public onlyIdentityIssuer(_identityIssuer) {
        IdentityIssuer storage identityIssuer = issuers[_identityIssuer];
        identityIssuer.level = Eidas.EidasLevel.Null;
        identityIssuer.active = false;
    }

    function getEidasLevel(address _identityIssuer) public constant onlyIdentityIssuer(_identityIssuer) returns (Eidas.EidasLevel) {
        return issuers[_identityIssuer].level;
    }

}

// File: contracts/libs/Owned.sol

pragma solidity 0.4.23;

contract Owned {
    address public owner;
    modifier onlyOwner() {
        require(isOwner(msg.sender));
        _;
    }

    constructor () public {
        owner = msg.sender;
    }

    function isOwner(address addr) public view returns(bool) {
        return addr == owner;
    }

    function transfer(address newOwner) public onlyOwner {
        if (newOwner != address(this)) {
            owner = newOwner;
        }
    }
}

// File: contracts/identityManager/AlastriaProxy.sol

pragma solidity 0.4.23;


contract AlastriaProxy is Owned {
    address public owner;
    address public recover;

    event Forwarded (address indexed destination, uint value, bytes data);
    event Received (address indexed sender, uint value);

    modifier onlyOwner() {
        require(isOwner(msg.sender));
        _;
    }

    modifier onlyOwnerOrRecover() {
        require(isOwner(msg.sender)||isRecover(msg.sender));
        _;
    }

    constructor () public {
        owner = msg.sender;
        recover = msg.sender;
    }

    function () payable public{
        emit Received(msg.sender, msg.value);
    }

    function forward(address destination, uint value, bytes data) public onlyOwner {
        require(destination.call.value(value)(data));
        emit Forwarded(destination, value, data);
    }

    function isRecover(address addr) public view returns(bool) {
        return addr == recover;
    }
}

// File: contracts/registry/AlastriaCredentialRegistry.sol

pragma solidity 0.4.23;


contract AlastriaCredentialRegistry {

    // SubjectCredential are registered under Hash(Credential) in a (subject, hash) mapping
    // IssuerCredentials are registered under Hash (Credentials + SubjectCredentialSignature) in a (issuer, hash) mapping
    // A List of Subject credential hashes is gathered in a (subject) mapping
    // To Think About: Make a unique Credential struct and just one mapping subjectCredentialRegistry instead one for subjects and one for issuers
    // To Do: Return credential URI. Should only be available to Subject. Mainly as a backup or main index when there are more than one device.
    // Could be done from credential mapping in another get function only for subject
    // or in getSubjectCredentialList (changing URI from one mapping to the other)
    // To Do: make AlastriaCredentialRegistry similar to AlastriaClaimRegistry.

    // Variables
    int public version;
    address public previousPublishedVersion;

    // SubjectCredential: Initially Valid: Only DeletedBySubject
    // IssuerCredentials: Initially Valid: Only AskIssuer or Revoked, no backwards transitions.
    enum Status {Valid, AskIssuer, Revoked, DeletedBySubject}
    Status constant STATUS_FIRST = Status.Valid;
    Status constant STATUS_LAST = Status.DeletedBySubject;

    struct SubjectCredential {
        bool exists;
        Status status;
        string URI;
    }

    // Mapping subject, hash (JSON credential)
    mapping(address => mapping(bytes32 => SubjectCredential)) private subjectCredentialRegistry;
    mapping(address => bytes32[]) private subjectCredentialList;

    struct IssuerCredential {
        bool exists;
        Status status;
    }

    // Mapping issuer, hash (JSON credential + CredentialSignature)
    mapping(address => mapping(bytes32 => IssuerCredential)) private issuerCredentialRegistry;

    // Events. Just for changes, not for initial set
    event SubjectCredentialDeleted (bytes32 subjectCredentialHash);
    event IssuerCredentialRevoked (bytes32 issuerCredentialHash, Status status);

    //Modifiers
    modifier validAddress(address addr) {//protects against some weird attacks
        require(addr != address(0));
        _;
    }

    modifier validStatus (Status status) { // solidity currently check on use not at function call
        require (status >= STATUS_FIRST && status <= STATUS_LAST);
        _;
    }

    // Functions
    constructor (address _previousPublishedVersion) public {
        version = 3;
        previousPublishedVersion = _previousPublishedVersion;
    }

    function addSubjectCredential(bytes32 subjectCredentialHash, string URI) public {
        require(!subjectCredentialRegistry[msg.sender][subjectCredentialHash].exists);
        subjectCredentialRegistry[msg.sender][subjectCredentialHash] = SubjectCredential(true, Status.Valid, URI);
        subjectCredentialList[msg.sender].push(subjectCredentialHash);
    }

    function deleteSubjectCredential(bytes32 subjectCredentialHash) public {
        SubjectCredential storage value = subjectCredentialRegistry[msg.sender][subjectCredentialHash];
        // only existent
        if (value.exists && value.status != Status.DeletedBySubject) {
            value.status = Status.DeletedBySubject;
            emit SubjectCredentialDeleted(subjectCredentialHash);
        }
    }

    // If the credential does not exists the return is a void credential
    // If we want a log, should we add an event?
    function getSubjectCredentialStatus(address subject, bytes32 subjectCredentialHash) view public validAddress(subject) returns (bool exists, Status status) {
        SubjectCredential storage value = subjectCredentialRegistry[subject][subjectCredentialHash];
        return (value.exists, value.status);
    }

    function getSubjectCredentialList() public view returns (uint, bytes32[]) {
        return (subjectCredentialList[msg.sender].length, subjectCredentialList[msg.sender]);
    }

    function updateCredentialStatus(bytes32 issuerCredentialHash, Status status) validStatus (status) public {
        IssuerCredential storage value = issuerCredentialRegistry[msg.sender][issuerCredentialHash];
        // No backward transition, only AskIssuer or Revoked
        if (status > value.status) {
            if (status == Status.AskIssuer || status == Status.Revoked) {
                value.exists = true;
                value.status = status;
                emit IssuerCredentialRevoked(issuerCredentialHash, status);
            }
        }
    }

    // If the credential does not exists the return is a void credential
    // If we want a log, should we add an event?
    function getIssuerCredentialStatus(address issuer, bytes32 issuerCredentialHash) view public validAddress(issuer) returns (bool exists, Status status) {
        IssuerCredential storage value = issuerCredentialRegistry[issuer][issuerCredentialHash];
        return (value.exists, value.status);
    }

    // Utility function
    // Defining three status functions avoid linking the subject to the issuer or the corresponding hashes
    function getCredentialStatus(Status subjectStatus, Status issuerStatus) pure public validStatus(subjectStatus) validStatus(issuerStatus) returns (Status){
        if (subjectStatus >= issuerStatus) {
            return subjectStatus;
        } else {
            return issuerStatus;
        }
    }
}

// File: contracts/registry/AlastriaPresentationRegistry.sol

pragma solidity 0.4.23;


contract AlastriaPresentationRegistry {

    // Subject Presentation actions are registered under subjectPresentationHash = hash(Presentation)
    // in a (subject, subjectPresentationHash) mapping
    // Receiver (ussually a Service Provider) Presentation Actions are registered
    // under receiverPresentationHash = hash(Presentations + PresentationSignature) in a (receiver, receiverPresentationHash) mapping
    // A List of Subject Presentation Hashes is gathered in a (subject) mapping
    // To Review: Subject Presentations  could be iterated instead of returned as an array


    // Variables
    int public version;
    address public previousPublishedVersion;


    // Status definition, should be moved to a Library.
    enum Status {Valid, Received, AskDeletion, DeletionConfirmation}
    Status constant STATUS_FIRST = Status.Valid;
    Status constant STATUS_LAST = Status.DeletionConfirmation;
    int constant STATUS_SIZE = 4;
    bool[STATUS_SIZE] subjectAllowed = [
        true,
        false,
        true,
        false
    ];
    bool[STATUS_SIZE] receiverAllowed = [
        false,
        true,
        false,
        true
    ];
    bool backTransitionsAllowed = false;


    // Presentation: Initially set to Valid
    // Updates as allowed in *allow arrays
    struct SubjectPresentation {
        bool exists;
        Status status;
        string URI;
    }
    // Mapping subject, subjectPresentationHash (Complete JSON Presentation)
    mapping(address => mapping(bytes32 => SubjectPresentation)) private subjectPresentationRegistry;
    mapping(address => bytes32[]) private subjectPresentationListRegistry;

    struct ReceiverPresentation {
        bool exists;
        Status status;
    }
    // Mapping receiver, receiverPresentationHash (Complete JSON Presentation + PresentationSignature)
    mapping(address => mapping(bytes32 => ReceiverPresentation)) private receiverPresentationRegistry;


    // Events. Just for changes, not for initial set
    event PresentationUpdated (bytes32 hash, Status status);


    //Modifiers
    modifier validAddress(address addr) {//protects against some weird attacks
        require(addr != address(0));
        _;
    }

    modifier validStatus (Status status) { // solidity currently check on use not at function call
        require (status >= STATUS_FIRST && status <= STATUS_LAST);
        _;
    }

    // Functions
    constructor (address _previousPublishedVersion) public {
        version = 3;
        previousPublishedVersion = _previousPublishedVersion;
    }

    //
    //Subject functions
    function addSubjectPresentation(bytes32 subjectPresentationHash, string URI) public {
        require(!subjectPresentationRegistry[msg.sender][subjectPresentationHash].exists);
        subjectPresentationRegistry[msg.sender][subjectPresentationHash] = SubjectPresentation(true, Status.Valid, URI);
        subjectPresentationListRegistry[msg.sender].push(subjectPresentationHash);
    }

    function updateSubjectPresentation(bytes32 subjectPresentationHash, Status status) public validStatus(status) {
        SubjectPresentation storage value = subjectPresentationRegistry[msg.sender][subjectPresentationHash];
        // Check existence and backtransitions, should be requires?
        if (!value.exists) {
            return;
        }
        if (!backTransitionsAllowed && status <= value.status) {
            return;
        }
        if (subjectAllowed[uint(status)]) {
            value.status = status;
            emit PresentationUpdated(subjectPresentationHash, status);
        }
    }

    // If the Presentation does not exists the return is a void Presentation
    // If we want a log, should we add an event?
    function getSubjectPresentationStatus(address subject, bytes32 subjectPresentationHash) view public validAddress(subject) returns (bool exists, Status status) {
        SubjectPresentation storage value = subjectPresentationRegistry[subject][subjectPresentationHash];
        return (value.exists, value.status);
    }

    function getSubjectPresentationList() public view returns (uint, bytes32[]) {
        return (subjectPresentationListRegistry[msg.sender].length, subjectPresentationListRegistry[msg.sender]);
    }

    //
    //Receiver functions
    function updateReceiverPresentation(bytes32 receiverPresentationHash, Status status) public validStatus(status) {
        ReceiverPresentation storage value = receiverPresentationRegistry[msg.sender][receiverPresentationHash];
        // No previous existence required. Check backward transition
        if (!backTransitionsAllowed && status <= value.status) {
            return;
        }
        if (receiverAllowed[uint(status)]) {
            value.exists = true;
            value.status = status;
            emit PresentationUpdated(receiverPresentationHash, status);
        }
    }

    // If the Presentation does not exists the return is a void Presentation
    // If we want a log, should we add an event?
    function getReceiverPresentationStatus(address receiver, bytes32 receiverPresentationHash) view public validAddress(receiver) returns (bool exists, Status status) {
        ReceiverPresentation storage value = receiverPresentationRegistry[receiver][receiverPresentationHash];
        return (value.exists, value.status);
    }

    // Utility function
    // Defining three status functions avoids linking the Subject to the Receiver or the corresponding hashes
    function getPresentationStatus(Status subjectStatus, Status receiverStatus) pure public validStatus(subjectStatus) validStatus(receiverStatus) returns (Status){
        if (subjectStatus >= receiverStatus) {
            return subjectStatus;
        } else {
            return receiverStatus;
        }
    }
}

// File: contracts/registry/AlastriaPublicKeyRegistry.sol

pragma solidity ^0.4.23;


contract AlastriaPublicKeyRegistry {

    // This contracts registers and makes publicly avalaible the AlastriaID Public Keys hash and status, current and past.

    //To Do: Should we add RevokedBySubject Status?

    //Variables
    int public version;
    address public previousPublishedVersion;

    // Initially Valid: could only be changed to DeletedBySubject for the time being.
    enum Status {Valid, DeletedBySubject}
    struct PublicKey {
        bool exists;
        Status status; // Deleted keys shouldnt be used, not even to check previous signatures.
        uint startDate;
        uint endDate;
    }

    // Mapping (subject, publickey)
    mapping(address => mapping(bytes32 => PublicKey)) private publicKeyRegistry;
    // mapping subject => publickey
    mapping(address => bytes32[]) public publicKeyList;

    //Events, just for revocation and deletion
    event PublicKeyDeleted (bytes32 publicKey);
    event PublicKeyRevoked (bytes32 publicKey);

    //Modifiers
    modifier validAddress(address addr) {//protects against some weird attacks
        require(addr != address(0));
        _;
    }

    //Functions
    constructor (address _previousPublishedVersion) public {
        version = 3;
        previousPublishedVersion = _previousPublishedVersion;
    }

    // Sets new key and revokes previous
    function addKey(bytes32 publicKey) public {
        require(!publicKeyRegistry[msg.sender][publicKey].exists);
        uint changeDate = now;
        revokePublicKey(getCurrentPublicKey(msg.sender));
        publicKeyRegistry[msg.sender][publicKey] = PublicKey(
            true,
            Status.Valid,
            changeDate,
            0
        );
        publicKeyList[msg.sender].push(publicKey);
    }

    function revokePublicKey(bytes32 publicKey) public {
        PublicKey storage value = publicKeyRegistry[msg.sender][publicKey];
        // only existent no backtransition
        if (value.exists && value.status != Status.DeletedBySubject) {
            value.endDate = now;
            emit PublicKeyRevoked(publicKey);
        }
    }

    function deletePublicKey(bytes32 publicKey) public {
        PublicKey storage value = publicKeyRegistry[msg.sender][publicKey];
        // only existent
        if (value.exists) {
            value.status = Status.DeletedBySubject;
            value.endDate = now;
            emit PublicKeyDeleted(publicKey);
        }
    }

    function getCurrentPublicKey(address subject) view public validAddress(subject) returns (bytes32) {
        if (publicKeyList[subject].length > 0) {
            return publicKeyList[subject][publicKeyList[subject].length - 1];
        } else {
            return 0;
        }
    }

    function getPublicKeyStatus(address subject, bytes32 publicKey) view public validAddress(subject)
        returns (bool exists, Status status, uint startDate, uint endDate){
        PublicKey storage value = publicKeyRegistry[subject][publicKey];
        return (value.exists, value.status, value.startDate, value.endDate);
    }

}

// File: contracts/identityManager/AlastriaIdentityManager.sol

pragma solidity 0.4.23;








contract AlastriaIdentityManager is AlastriaIdentityServiceProvider, AlastriaIdentityIssuer, Owned {
    //Variables
    uint256 public version;
    uint internal timeToLive = 10000;
    AlastriaCredentialRegistry public alastriaCredentialRegistry;
    AlastriaPresentationRegistry public alastriaPresentationRegistry;
    AlastriaPublicKeyRegistry public alastriaPublicKeyRegistry;
    mapping(address => address) public identityKeys; //change to alastriaID created check bool
    mapping(address => uint) internal accessTokens;

    //Events
    event AccessTokenGenerated(address indexed signAddress);

    event OperationWasNotSupported(string indexed method);

    event IdentityCreated(address indexed identity, address indexed creator, address owner);

    //Modifiers
    modifier isOnTimeToLiveAndIsFromCaller(address _signAddress) {
        require(accessTokens[_signAddress] > 0 && accessTokens[_signAddress] > now);
        _;
    }

    modifier validAddress(address addr) { //protects against some weird attacks
        require(addr != address(0));
        _;
    }

    //Constructor
    constructor (uint256 _version) public{
        //TODO require(_version > getPreviousVersion(_previousVersion));
        alastriaCredentialRegistry = new AlastriaCredentialRegistry(address(0));
        alastriaPresentationRegistry = new AlastriaPresentationRegistry(address(0));
        alastriaPublicKeyRegistry = new AlastriaPublicKeyRegistry(address(0));
        version = _version;
    }

    //Methods
    function generateAccessToken(address _signAddress) public onlyIdentityServiceProvider(msg.sender) {
        accessTokens[_signAddress] = now + timeToLive;
        emit AccessTokenGenerated(_signAddress);
    }

    /// @dev Creates a new AlastriaProxy contract for an owner and recovery and allows an initial forward call which would be to set the registry in our case
    /// @param destination Address of contract to be called after AlastriaProxy is created
    /// @param publicKeyData of function to be called at the destination contract
    function createAlastriaIdentity(address destination, bytes publicKeyData) public validAddress(msg.sender) isOnTimeToLiveAndIsFromCaller(msg.sender) {
        AlastriaProxy identity = createIdentity(msg.sender, address(this));
        accessTokens[msg.sender] = 0;
        identity.forward(destination, 0, publicKeyData);//must be alastria registry call
    } 

    /// @dev This method would be private in production
    function createIdentity(address owner, address recoveryKey) public returns (AlastriaProxy identity){
        identity = new AlastriaProxy();
        identityKeys[msg.sender] = identity;
        emit IdentityCreated(identity, recoveryKey, owner);
    }

    /// @dev This method send a transaction trough the proxy of the sender
    function delegateCall(address _destination, uint256 _value, bytes _data) public {
        require(identityKeys[msg.sender]!=address(0));
        identityKeys[msg.sender].call(bytes4(keccak256("forward(address,uint256,bytes)")),_destination,_value,_data);
    }

    //Internals TODO: warning recommending change visibility to pure
    //Checks that address a is the first input in msg.data.
    //Has very minimal gas overhead.
    function checkMessageData(address a) internal pure returns (bool t) {
        if (msg.data.length < 36) return false;
        assembly {
            let mask := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
            t := eq(a, and(mask, calldataload(4)))
        }
    }
}