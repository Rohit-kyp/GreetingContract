// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title GreetingContract
 * @dev Smart contract for storing and managing personalized greeting messages
 * @author Greeting Platform Team
 */
contract GreetingContract is Ownable, Pausable, ReentrancyGuard {
    
    // Struct to represent a greeting
    struct Greeting {
        string message;
        address sender;
        uint256 timestamp;
        bool isPublic;
        uint256 likeCount;
        string category;
        string language;
    }
    
    // Struct to represent user profile
    struct UserProfile {
        string username;
        string bio;
        uint256 totalGreetings;
        uint256 totalLikes;
        bool isVerified;
        uint256 joinDate;
    }
    
    // State variables
    mapping(address => string) private personalGreetings;
    mapping(address => UserProfile) public userProfiles;
    mapping(uint256 => Greeting) public publicGreetings;
    mapping(uint256 => mapping(address => bool)) public hasLiked;
    mapping(address => uint256[]) public userGreetingIds;
    mapping(string => uint256[]) public greetingsByCategory;
    mapping(address => mapping(address => string)) public directGreetings;
    
    uint256 private greetingIdCounter;
    uint256 public totalPublicGreetings;
    uint256 public updateFee = 0.001 ether;
    string public defaultGreeting = "Hello, World!";
    
    // Arrays for categories and supported languages
    string[] public supportedCategories = ["General", "Birthday", "Holiday", "Love", "Friendship", "Business", "Motivational"];
    string[] public supportedLanguages = ["English", "Spanish", "French", "German", "Italian", "Portuguese", "Chinese", "Japanese"];
    
    // Events
    event GreetingSet(address indexed user, string greeting, uint256 timestamp);
    event PublicGreetingCreated(uint256 indexed greetingId, address indexed sender, string message, string category);
    event GreetingLiked(uint256 indexed greetingId, address indexed liker, uint256 totalLikes);
    event DirectGreetingSent(address indexed from, address indexed to, string message);
    event UserProfileUpdated(address indexed user, string username, string bio);
    event UserVerified(address indexed user);
    
    /**
     * @dev Constructor to initialize the greeting contract
     */
    constructor() Ownable(msg.sender) {
        greetingIdCounter = 0;
        totalPublicGreetings = 0;
    }
    
    /**
     * @dev Core Function 1: Set personal greeting message
     * @param _greeting The greeting message to set
     */
    function setGreeting(string memory _greeting) external payable whenNotPaused {
        require(bytes(_greeting).length > 0, "Greeting cannot be empty");
        require(bytes(_greeting).length <= 280, "Greeting too long (max 280 characters)");
        
        // Check if fee is required for updates (after first greeting)
        if (bytes(personalGreetings[msg.sender]).length > 0) {
            require(msg.value >= updateFee, "Insufficient fee for greeting update");
        }
        
        personalGreetings[msg.sender] = _greeting;
        
        // Update user profile
        if (bytes(userProfiles[msg.sender].username).length == 0) {
            userProfiles[msg.sender] = UserProfile({
                username: "",
                bio: "",
                totalGreetings: 1,
                totalLikes: 0,
                isVerified: false,
                joinDate: block.timestamp
            });
        } else {
            userProfiles[msg.sender].totalGreetings++;
        }
        
        // Transfer update fee to owner
        if (msg.value > 0) {
            payable(owner()).transfer(msg.value);
        }
        
        emit GreetingSet(msg.sender, _greeting, block.timestamp);
    }
    
    /**
     * @dev Core Function 2: Get greeting message for any address
     * @param _user Address of the user whose greeting to retrieve
     * @return The greeting message or default if none set
     */
    function getGreeting(address _user) external view returns (string memory) {
        if (bytes(personalGreetings[_user]).length == 0) {
            return defaultGreeting;
        }
        return personalGreetings[_user];
    }
    
    /**
     * @dev Core Function 3: Create a public greeting with category
     * @param _message The greeting message
     * @param _category Category of the greeting
     * @param _language Language of the greeting
     * @return greetingId The ID of the created public greeting
     */
    function createPublicGreeting(
        string memory _message, 
        string memory _category,
        string memory _language
    ) external whenNotPaused returns (uint256) {
        require(bytes(_message).length > 0, "Message cannot be empty");
        require(bytes(_message).length <= 500, "Message too long (max 500 characters)");
        require(_isValidCategory(_category), "Invalid category");
        require(_isValidLanguage(_language), "Invalid language");
        
        greetingIdCounter++;
        uint256 newGreetingId = greetingIdCounter;
        
        publicGreetings[newGreetingId] = Greeting({
            message: _message,
            sender: msg.sender,
            timestamp: block.timestamp,
            isPublic: true,
            likeCount: 0,
            category: _category,
            language: _language
        });
        
        userGreetingIds[msg.sender].push(newGreetingId);
        greetingsByCategory[_category].push(newGreetingId);
        totalPublicGreetings++;
        
        emit PublicGreetingCreated(newGreetingId, msg.sender, _message, _category);
        return newGreetingId;
    }
    
    /**
     * @dev Like a public greeting
     * @param _greetingId ID of the greeting to like
     */
    function likeGreeting(uint256 _greetingId) external whenNotPaused {
        require(_greetingId > 0 && _greetingId <= greetingIdCounter, "Invalid greeting ID");
        require(publicGreetings[_greetingId].sender != address(0), "Greeting does not exist");
        require(!hasLiked[_greetingId][msg.sender], "Already liked this greeting");
        require(publicGreetings[_greetingId].sender != msg.sender, "Cannot like your own greeting");
        
        hasLiked[_greetingId][msg.sender] = true;
        publicGreetings[_greetingId].likeCount++;
        
        // Update sender's profile likes
        address greetingSender = publicGreetings[_greetingId].sender;
        userProfiles[greetingSender].totalLikes++;
        
        emit GreetingLiked(_greetingId, msg.sender, publicGreetings[_greetingId].likeCount);
    }
    
    /**
     * @dev Send a direct greeting to another user
     * @param _recipient Address of the recipient
     * @param _message The greeting message
     */
    function sendDirectGreeting(address _recipient, string memory _message) external whenNotPaused {
        require(_recipient != address(0), "Invalid recipient address");
        require(_recipient != msg.sender, "Cannot send greeting to yourself");
        require(bytes(_message).length > 0, "Message cannot be empty");
        require(bytes(_message).length <= 280, "Message too long (max 280 characters)");
        
        directGreetings[msg.sender][_recipient] = _message;
        
        emit DirectGreetingSent(msg.sender, _recipient, _message);
    }
    
    /**
     * @dev Get direct greeting between two users
     * @param _sender Address of the sender
     * @param _recipient Address of the recipient
     * @return The direct greeting message
     */
    function getDirectGreeting(address _sender, address _recipient) external view returns (string memory) {
        require(_sender != address(0) && _recipient != address(0), "Invalid addresses");
        return directGreetings[_sender][_recipient];
    }
    
    /**
     * @dev Update user profile information
     * @param _username Username for the profile
     * @param _bio Bio description for the profile
     */
    function updateProfile(string memory _username, string memory _bio) external whenNotPaused {
        require(bytes(_username).length > 0 && bytes(_username).length <= 50, "Invalid username length");
        require(bytes(_bio).length <= 200, "Bio too long (max 200 characters)");
        
        // Initialize profile if it doesn't exist
        if (userProfiles[msg.sender].joinDate == 0) {
            userProfiles[msg.sender] = UserProfile({
                username: _username,
                bio: _bio,
                totalGreetings: 0,
                totalLikes: 0,
                isVerified: false,
                joinDate: block.timestamp
            });
        } else {
            userProfiles[msg.sender].username = _username;
            userProfiles[msg.sender].bio = _bio;
        }
        
        emit UserProfileUpdated(msg.sender, _username, _bio);
    }
    
    /**
     * @dev Get user's public greetings
     * @param _user Address of the user
     * @return Array of greeting IDs
     */
    function getUserGreetings(address _user) external view returns (uint256[] memory) {
        return userGreetingIds[_user];
    }
    
    /**
     * @dev Get greetings by category
     * @param _category Category to filter by
     * @return Array of greeting IDs
     */
    function getGreetingsByCategory(string memory _category) external view returns (uint256[] memory) {
        require(_isValidCategory(_category), "Invalid category");
        return greetingsByCategory[_category];
    }
    
        /**
     * @dev Get public greeting details
     * @param _greetingId ID of the greeting
     * @return message The greeting message
     * @return sender Address of the greeting sender
     * @return timestamp When the greeting was created
     * @return likeCount Number of likes for the greeting
     * @return category Category of the greeting
     * @return language Language of the greeting
     */
    function getPublicGreeting(uint256 _greetingId) external view returns (
        string memory message,
        address sender,
        uint256 timestamp,
        uint256 likeCount,
        string memory category,
        string memory language
    ) {
        require(_greetingId > 0 && _greetingId <= greetingIdCounter, "Invalid greeting ID");
        require(publicGreetings[_greetingId].sender != address(0), "Greeting does not exist");
        
        Greeting memory greeting = publicGreetings[_greetingId];
        return (
            greeting.message,
            greeting.sender,
            greeting.timestamp,
            greeting.likeCount,
            greeting.category,
            greeting.language
        );
    }
    
        /**
     * @dev Get user profile information
     * @param _user Address of the user
     * @return username The username of the user
     * @return bio The bio description of the user
     * @return totalGreetings The total number of greetings sent by the user
     * @return totalLikes The total number of likes received by the user
     * @return isVerified Whether the user is verified
     * @return joinDate The date when the user joined
     */
    function getUserProfile(address _user) external view returns (
        string memory username,
        string memory bio,
        uint256 totalGreetings,
        uint256 totalLikes,
        bool isVerified,
        uint256 joinDate
    ) {
        UserProfile memory profile = userProfiles[_user];
        return (
            profile.username,
            profile.bio,
            profile.totalGreetings,
            profile.totalLikes,
            profile.isVerified,
            profile.joinDate
        );
    }
    
    /**
     * @dev Get most liked greetings (top 10)
     * @return Array of greeting IDs sorted by like count
     */
    function getMostLikedGreetings() external view returns (uint256[] memory) {
        uint256[] memory topGreetings = new uint256[](10);
        uint256[] memory topLikes = new uint256[](10);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= greetingIdCounter && count < 10; i++) {
            if (publicGreetings[i].sender != address(0)) {
                uint256 likes = publicGreetings[i].likeCount;
                
                // Find position to insert
                uint256 pos = count;
                for (uint256 j = 0; j < count; j++) {
                    if (likes > topLikes[j]) {
                        pos = j;
                        break;
                    }
                }
                
                // Shift elements and insert
                if (pos < 10) {
                    for (uint256 k = (count < 9 ? count : 9); k > pos; k--) {
                        topGreetings[k] = topGreetings[k-1];
                        topLikes[k] = topLikes[k-1];
                    }
                    topGreetings[pos] = i;
                    topLikes[pos] = likes;
                    if (count < 10) count++;
                }
            }
        }
        
        // Return only filled positions
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = topGreetings[i];
        }
        
        return result;
    }
    
    /**
     * @dev Get recent public greetings (last 20)
     * @return Array of greeting IDs in reverse chronological order
     */
    function getRecentGreetings() external view returns (uint256[] memory) {
        uint256 count = totalPublicGreetings > 20 ? 20 : totalPublicGreetings;
        uint256[] memory recentGreetings = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = greetingIdCounter; i > 0 && index < count; i--) {
            if (publicGreetings[i].sender != address(0)) {
                recentGreetings[index] = i;
                index++;
            }
        }
        
        return recentGreetings;
    }
    
    /**
     * @dev Check if category is valid
     * @param _category Category to validate
     * @return True if category is supported
     */
    function _isValidCategory(string memory _category) internal view returns (bool) {
        for (uint256 i = 0; i < supportedCategories.length; i++) {
            if (keccak256(bytes(supportedCategories[i])) == keccak256(bytes(_category))) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @dev Check if language is valid
     * @param _language Language to validate
     * @return True if language is supported
     */
    function _isValidLanguage(string memory _language) internal view returns (bool) {
        for (uint256 i = 0; i < supportedLanguages.length; i++) {
            if (keccak256(bytes(supportedLanguages[i])) == keccak256(bytes(_language))) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @dev Verify a user (only owner)
     * @param _user Address of the user to verify
     */
    function verifyUser(address _user) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(userProfiles[_user].joinDate > 0, "User profile does not exist");
        
        userProfiles[_user].isVerified = true;
        emit UserVerified(_user);
    }
    
    /**
     * @dev Update default greeting (only owner)
     * @param _newDefault New default greeting message
     */
    function updateDefaultGreeting(string memory _newDefault) external onlyOwner {
        require(bytes(_newDefault).length > 0, "Default greeting cannot be empty");
        defaultGreeting = _newDefault;
    }
    
    /**
     * @dev Update update fee (only owner)
     * @param _newFee New fee for greeting updates
     */
    function updateUpdateFee(uint256 _newFee) external onlyOwner {
        updateFee = _newFee;
    }
    
    /**
     * @dev Add new supported category (only owner)
     * @param _category New category to add
     */
    function addSupportedCategory(string memory _category) external onlyOwner {
        require(bytes(_category).length > 0, "Category cannot be empty");
        require(!_isValidCategory(_category), "Category already exists");
        
        supportedCategories.push(_category);
    }
    
    /**
     * @dev Add new supported language (only owner)
     * @param _language New language to add
     */
    function addSupportedLanguage(string memory _language) external onlyOwner {
        require(bytes(_language).length > 0, "Language cannot be empty");
        require(!_isValidLanguage(_language), "Language already exists");
        
        supportedLanguages.push(_language);
    }
    
    /**
     * @dev Get all supported categories
     * @return Array of supported categories
     */
    function getSupportedCategories() external view returns (string[] memory) {
        return supportedCategories;
    }
    
    /**
     * @dev Get all supported languages
     * @return Array of supported languages
     */
    function getSupportedLanguages() external view returns (string[] memory) {
        return supportedLanguages;
    }
    
       /**
     * @dev Get contract statistics
     * @return totalUsers The total number of users
     * @return totalPublicGreetingsCount The total number of public greetings
     * @return totalCategories The total number of supported categories
     * @return totalLanguages The total number of supported languages
     */
    function getContractStats() external view returns (
        uint256 totalUsers,
        uint256 totalPublicGreetingsCount,
        uint256 totalCategories,
        uint256 totalLanguages
    ) {
        // Count users by iterating through greeting counter
        uint256 userCount = 0;
        for (uint256 i = 1; i <= greetingIdCounter; i++) {
            if (publicGreetings[i].sender != address(0)) {
                userCount++;
            }
        }
        
        return (
            userCount,
            totalPublicGreetings,
            supportedCategories.length,
            supportedLanguages.length
        );
    }
    
    /**
     * @dev Pause contract (only owner)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause contract (only owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        payable(owner()).transfer(balance);
    }
}
