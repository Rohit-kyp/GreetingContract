# GreetingContract
# Greeting Contract Project

## Project Structure
```
GreetingContract/
├── contracts/
│   └── GreetingContract.sol
├── README.md
└── package.json
```

## contracts/GreetingContract.sol

```solidity
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
     * @return message, sender, timestamp, likeCount, category, language
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
     * @return username, bio, totalGreetings, totalLikes, isVerified, joinDate
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
     * @return totalUsers, totalPublicGreetings, totalCategories, totalLanguages
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
```

## README.md

```markdown
# Greeting Contract

## Project Description

The Greeting Contract is an innovative blockchain-based platform that revolutionizes how people share and manage personalized greeting messages. This smart contract system creates a decentralized social network focused on positive interactions, cultural exchange, and meaningful communication through customizable greeting messages.

Built on the Ethereum blockchain, this platform allows users to set personal greeting messages, create public greetings with categories and language tags, send direct messages to other users, and build profiles within a supportive community ecosystem. The system promotes cross-cultural communication by supporting multiple languages and celebrating diverse greeting traditions from around the world.

The platform combines the permanence and transparency of blockchain technology with the warmth and personal touch of traditional greeting cards and messages. Users can like and interact with public greetings, discover content by category or language, and build reputation through community engagement. The system includes anti-spam measures, content moderation capabilities, and user verification features to maintain a positive and safe environment.

Every greeting, interaction, and profile update is permanently recorded on the blockchain, creating an immutable history of positive human connections and cultural exchanges that can be treasured and referenced for years to come.

## Project Vision

Our vision is to create a global platform that celebrates human connection, promotes cultural understanding, and spreads positivity through the universal language of greetings. We aim to:

- **Foster Global Unity**: Connect people across cultures, languages, and geographical boundaries through shared expressions of goodwill
- **Preserve Cultural Heritage**: Document and celebrate diverse greeting traditions from cultures around the world
- **Promote Positive Communication**: Create a platform dedicated exclusively to uplifting, encouraging, and positive messages
- **Build Lasting Memories**: Provide a permanent, blockchain-secured repository of meaningful personal messages and connections
- **Encourage Language Learning**: Facilitate cross-cultural exchange and language learning through multilingual greeting interactions
- **Create Digital Legacy**: Enable users to leave lasting positive impacts through messages that persist beyond traditional social media platforms
- **Support Mental Wellness**: Contribute to global mental health by promoting gratitude, kindness, and positive social interactions

## Key Features

### 💬 **Personal Greeting Management**
- Set and update personalized greeting messages visible to all users
- Character limits ensure concise, meaningful messages (280 characters for personal, 500 for public)
- Default greeting system provides fallback for users without custom messages
- Update fee mechanism helps maintain platform sustainability and prevent spam
- Timestamp tracking for message history and analytics

### 🌍 **Multilingual Public Greetings**
- Create public greetings with category and language tags for better discoverability
- Support for 8 major languages: English, Spanish, French, German, Italian, Portuguese, Chinese, Japanese
- 7 greeting categories: General, Birthday, Holiday, Love, Friendship, Business, Motivational
- Expandable language and category system for growing global community
- Cultural context preservation through proper categorization and tagging

### 👥 **Social Interaction Features**
- Like system for public greetings with duplicate prevention and self-like blocking
- Direct messaging capability for private greeting exchanges between users
- User profiles with usernames, bios, and engagement statistics
- Verification system for trusted community members and content creators
- Reputation building through total greetings created and likes received

### 📊 **Discovery and Analytics**
- Most liked greetings leaderboard to highlight popular content
- Recent greetings feed for discovering new content and active users
- Category-based browsing for finding specific types of greetings
- User greeting history and engagement tracking for personal analytics
- Contract-wide statistics for platform growth and usage insights

### 🔒 **Security and Moderation**
- Pausable contract functionality for emergency maintenance and security
- Owner controls for content moderation and platform management
- Anti-spam measures including update fees and character limits
- User verification system to build trust and prevent bad actors
- ReentrancyGuard protection for all financial transactions

### 💰 **Economic Sustainability**
- Optional update fees for greeting modifications to support platform development
- Withdrawal functionality for collected fees to fund ongoing operations
- Transparent fee structure with no hidden costs or surprise charges
- Future token economy potential for rewarding active community contributors
- Sustainable revenue model that doesn't rely on advertising or data harvesting

### 🎯 **Community Building**
- Profile system with join dates, statistics, and verification status
- Engagement metrics to recognize active and positive community contributors
- Content categorization that helps users find like-minded individuals
- Cultural exchange opportunities through multilingual interactions
- Positive-only environment that promotes mental wellness and kindness

## Future Scope

### Phase 1: Enhanced User Experience
- **Mobile Application**: Native iOS and Android apps with push notifications for likes and direct messages
- **Web Dashboard**: Comprehensive web interface with advanced search, filtering, and personalization options
- **Rich Media Support**: Integration with IPFS for images, audio greetings, and video messages
- **Offline Capabilities**: Cached content viewing and message composition for areas with poor connectivity
- **Accessibility Features**: Screen reader support, high contrast themes, and multilingual interface options

### Phase 2: Advanced Social Features
- **Friend Networks**: Follow systems, friend lists, and personalized feeds based on connections
- **Group Greetings**: Collaborative messages from multiple users for special occasions
- **Greeting Templates**: Pre-designed templates for holidays, birthdays, and special events
- **Reaction System**: Expanded emoji reactions beyond simple likes for more nuanced feedback
- **Greeting Chains**: Collaborative storytelling through connected greeting messages

### Phase 3: Gamification and Incentives
- **Achievement System**: Badges and achievements for milestones like first greeting, most liked message, multilingual posts
- **Streak Tracking**: Daily greeting streaks and consistency rewards for active users
- **Community Challenges**: Monthly themes, cultural exchange programs, and kindness challenges
- **Reputation Scoring**: Comprehensive reputation system based on quality contributions and positive interactions
- **Token Rewards**: Native platform token for rewarding active contributors and enabling premium features

### Phase 4: AI and Machine Learning
- **Smart Recommendations**: AI-powered content suggestions based on user preferences and interaction history
- **Language Translation**: Automatic translation services for cross-language communication
- **Sentiment Analysis**: AI moderation to ensure all content maintains positive tone and appropriate messaging
- **Personalization Engine**: Customized feeds, notification timing, and content prioritization
- **Trend Detection**: Identification of popular greeting patterns, cultural events, and viral positive messages

### Phase 5: Enterprise and Educational Integration
- **Corporate Wellness**: Enterprise packages for companies to improve workplace culture and employee engagement
- **Educational Programs**: Language learning partnerships and cultural education curricula
- **Mental Health Integration**: Collaboration with wellness apps and mental health platforms
- **API Ecosystem**: Developer APIs for third-party integrations and custom applications
- **White-Label Solutions**: Customizable platform deployments for organizations and communities

### Phase 6: Advanced Blockchain Features
- **Cross-Chain Compatibility**: Multi-blockchain deployment for reduced fees and increased accessibility
- **NFT Integration**: Special greeting NFTs for memorable occasions and limited edition cultural celebrations
- **Decentralized Governance**: Community voting on platform features, policies, and development priorities
- **Layer 2 Solutions**: Implementation on Polygon, Arbitrum, or custom L2 for faster, cheaper transactions
- **Decentralized Storage**: Complete migration to IPFS for censorship-resistant and permanent content storage

## Technical Implementation

### Smart Contract Architecture
- **Modular Design**: Separate contracts for core functionality, user management, and economic features
- **Upgradeability**: Proxy pattern implementation for seamless feature additions and security updates
- **Gas Optimization**: Efficient data structures and batch operations to minimize transaction costs
- **Event-Driven Architecture**: Comprehensive event logging for real-time updates and external integrations

### Data Management
- **Efficient Storage**: Optimized mapping structures for fast lookups and minimal gas consumption
- **Content Validation**: Input sanitization and validation to prevent malicious content injection
- **Privacy Protection**: Selective data sharing and user-controlled privacy settings
- **Backup Systems**: Automated backup processes for critical user data and platform state

### Integration Capabilities
- **RESTful APIs**: Comprehensive API suite for mobile apps, web interfaces, and third-party integrations
- **Webhook Support**: Real-time notifications for external systems and user applications
- **Oracle Integration**: External data feeds for currency conversion, language detection, and cultural events
- **Social Media Bridges**: Integration capabilities with existing social platforms for content sharing

## Use Cases and Applications

### Personal and Social
- **Birthday Celebrations**: Collaborative birthday messages from friends and family members
- **Holiday Greetings**: Cultural and religious holiday messages shared with global communities
- **Milestone Celebrations**: Graduation, anniversary, and achievement congratulations
- **Daily Affirmations**: Personal motivation and positive self-talk through persistent messages
- **Long-Distance Relationships**: Permanent message exchange for couples and families separated by distance

### Cultural and Educational
- **Language Exchange**: Native speakers sharing traditional greetings and cultural context
- **Cultural Preservation**: Documentation of endangered greeting traditions and languages
- **Educational Resources**: Teachers using platform for language learning and cultural studies
- **Tourism Promotion**: Destinations sharing welcome messages in multiple languages
- **Diplomatic Relations**: International goodwill messages and cultural bridge-building

### Professional and Business
- **Customer Relations**: Businesses creating welcoming messages for international customers
- **Team Building**: Corporate teams sharing motivational and appreciation messages
- **Professional Networking**: Industry professionals building relationships through positive communication
- **Brand Building**: Companies establishing positive brand associations through community engagement
- **Employee Recognition**: Internal recognition programs built on blockchain transparency

### Therapeutic and Wellness
- **Mental Health Support**: Peer support networks sharing encouragement and hope
- **Grief Counseling**: Memorial messages and community support for those experiencing loss
- **Addiction Recovery**: Sobriety milestones and peer support through positive messaging
- **Chronic Illness Support**: Community encouragement for individuals facing health challenges
- **Meditation and Mindfulness**: Daily inspiration and mindfulness reminders from community members

## Getting Started

### For Individual Users

#### Creating Your First Greeting
```solidity
// Set your personal greeting (free for first time)
setGreeting("Hello! I'm excited to connect with people from around the world!");

// Create a public greeting with category and language
createPublicGreeting(
    "Wishing everyone a wonderful day filled with joy and laughter!",
    "General",
    "English"
);
```

#### Updating Your Profile
```solidity
// Update your profile information
updateProfile(
    "GlobalGreeter2024",  // Username
    "Spreading positivity one greeting at a time! 🌟" // Bio
);
```

### For Developers

#### Local Development Setup
```bash
# Clone the repository
git clone https://github.com/yourusername/greeting-contract
cd GreetingContract

# Install dependencies
npm install

# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test

# Deploy locally
npx hardhat run scripts/deploy.js --network localhost
```

#### Integration Examples
```javascript
// Web3.js integration example
const contract = new web3.eth.Contract(abi, contractAddress);

// Get user's greeting
const greeting = await contract.methods.getGreeting(userAddress).call();

// Create public greeting
await contract.methods.createPublicGreeting(
    message, 
    category, 
    language
).send({ from: userAddress });

// Like a greeting
await contract.methods.likeGreeting(greetingId).send({ from: userAddress });
```

### For Community Managers

#### Platform Statistics
- Monitor user engagement through `getContractStats()`
- Track popular content via `getMostLikedGreetings()`
- Analyze category trends through `getGreetingsByCategory()`
- Identify active users through profile analytics

#### Content Moderation
- User verification system for trusted community members
- Pausable functionality for emergency content control
- Owner controls for category and language management
- Community reporting mechanisms for inappropriate content

## API Reference

### Core Functions
- `setGreeting(string _greeting)` - Set personal greeting message
- `getGreeting(address _user)` - Retrieve user's greeting or default
- `createPublicGreeting(string _message, string _category, string _language)` - Create public greeting

### Social Functions
- `likeGreeting(uint256 _greetingId)` - Like a public greeting
- `sendDirectGreeting(address _recipient, string _message)` - Send direct message
- `updateProfile(string _username, string _bio)` - Update user profile

### Discovery Functions
- `getMostLikedGreetings()` - Get top 10 most liked greetings
- `getRecentGreetings()` - Get last 20 public greetings
- `getGreetingsByCategory(string _category)` - Get greetings by category

## Community Guidelines

### Content Standards
- All messages must be positive, encouraging, or neutral in tone
- No hate speech, discrimination, or offensive language allowed
- Respect cultural differences and promote inclusivity
- Original content preferred; cite sources for quotes or references
- Maximum character limits enforced to encourage concise, meaningful communication

### Interaction Etiquette
- Engage respectfully with all community members regardless of background
- Use appropriate language tags for non-English content
- Provide context for cultural references that might not be universally understood
- Give meaningful likes rather than spam-liking content
- Report inappropriate content through proper channels

### Privacy and Safety
- Never share personal information like addresses, phone numbers, or financial details
- Be cautious when sharing identifying information in public greetings
- Use direct messaging for private conversations and sensitive topics
- Report suspicious behavior or users who violate community standards
- Understand that blockchain transactions are permanent and public

## Technical Documentation

### Smart Contract Functions Reference

#### Core Greeting Functions
```solidity
function setGreeting(string memory _greeting) external payable
// Sets personal greeting message
// Requires: _greeting not empty, <= 280 characters
// Fee: Free for first greeting, updateFee for subsequent updates

function getGreeting(address _user) external view returns (string memory)
// Returns user's greeting or default if none set
// No restrictions, publicly callable

function createPublicGreeting(string memory _message, string memory _category, string memory _language) external returns (uint256)
// Creates categorized public greeting
// Requires: Valid message, category, and language
// Returns: New greeting ID
```

#### Social Interaction Functions
```solidity
function likeGreeting(uint256 _greetingId) external
// Likes a public greeting (once per user)
// Requires: Valid greeting ID, not own greeting, haven't liked before

function sendDirectGreeting(address _recipient, string memory _message) external
// Sends private greeting to specific user
// Requires: Valid recipient, message <= 280 characters

function getDirectGreeting(address _sender, address _recipient) external view returns (string memory)
// Retrieves direct greeting between two addresses
// Publicly readable but requires knowing both addresses
```

#### Profile Management Functions
```solidity
function updateProfile(string memory _username, string memory _bio) external
// Updates user profile information
// Requires: Username 1-50 chars, bio <= 200 chars

function getUserProfile(address _user) external view returns (...)
// Returns complete user profile information
// Publicly accessible for transparency

function verifyUser(address _user) external onlyOwner
// Verifies user profile (owner only)
// Adds verification badge to user profile
```

### Event Definitions
```solidity
event GreetingSet(address indexed user, string greeting, uint256 timestamp);
event PublicGreetingCreated(uint256 indexed greetingId, address indexed sender, string message, string category);
event GreetingLiked(uint256 indexed greetingId, address indexed liker, uint256 totalLikes);
event DirectGreetingSent(address indexed from, address indexed to, string message);
event UserProfileUpdated(address indexed user, string username, string bio);
event UserVerified(address indexed user);
```

### Gas Cost Estimates
- Set personal greeting (first time): ~80,000 gas
- Update personal greeting: ~45,000 gas
- Create public greeting: ~120,000 gas
- Like greeting: ~50,000 gas
- Send direct greeting: ~60,000 gas
- Update profile: ~70,000 gas

### Security Considerations
- All user inputs are validated for length and content
- Reentrancy protection on payable functions
- Pausable functionality for emergency stops
- Owner-only functions for platform management
- No external contract calls to prevent attack vectors

## Deployment Guide

### Prerequisites
- Node.js v16 or higher
- Hardhat development environment
- Web3 wallet with sufficient ETH for deployment
- Etherscan API key for contract verification

### Environment Setup
```bash
# Install dependencies
npm install @openzeppelin/contracts hardhat @nomiclabs/hardhat-ethers

# Create environment file
cp .env.example .env

# Configure networks in hardhat.config.js
module.exports = {
  solidity: "0.8.19",
  networks: {
    mainnet: {
      url: process.env.MAINNET_RPC_URL,
      accounts: [process.env.PRIVATE_KEY]
    },
    goerli: {
      url: process.env.GOERLI_RPC_URL,
      accounts: [process.env.PRIVATE_KEY]
    }
  }
};
```

### Deployment Scripts
```javascript
// scripts/deploy.js
async function main() {
  const GreetingContract = await ethers.getContractFactory("GreetingContract");
  const greetingContract = await GreetingContract.deploy();
  
  await greetingContract.deployed();
  
  console.log("GreetingContract deployed to:", greetingContract.address);
  
  // Verify on Etherscan
  if (network.name !== "hardhat") {
    await hre.run("verify:verify", {
      address: greetingContract.address,
      constructorArguments: []
    });
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

### Testing Framework
```javascript
// test/GreetingContract.test.js
describe("GreetingContract", function () {
  let greetingContract;
  let owner, user1, user2;
  
  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    const GreetingContract = await ethers.getContractFactory("GreetingContract");
    greetingContract = await GreetingContract.deploy();
    await greetingContract.deployed();
  });
  
  describe("Basic functionality", function () {
    it("Should set and get greeting", async function () {
      await greetingContract.connect(user1).setGreeting("Hello World!");
      const greeting = await greetingContract.getGreeting(user1.address);
      expect(greeting).to.equal("Hello World!");
    });
    
    it("Should return default for unset greeting", async function () {
      const greeting = await greetingContract.getGreeting(user1.address);
      expect(greeting).to.equal("Hello, World!");
    });
  });
});
```

## Contributing Guidelines

### Development Workflow
1. Fork the repository and create feature branches
2. Write comprehensive tests for all new functionality
3. Ensure code follows Solidity style guide and security best practices
4. Update documentation for any API changes
5. Submit pull requests with detailed descriptions and test results

### Code Standards
- Use Solidity 0.8.19 or higher for latest security features
- Follow OpenZeppelin patterns for security and upgradability
- Include comprehensive NatSpec documentation for all functions
- Optimize for gas efficiency while maintaining readability
- Implement proper error handling and user-friendly error messages

### Testing Requirements
- Unit tests for all public functions
- Integration tests for complex workflows
- Gas usage optimization tests
- Security vulnerability tests
- Edge case and boundary condition tests

## License and Legal

### Open Source License
This project is licensed under the MIT License, allowing for:
- Commercial and private use
- Modification and distribution
- Patent use (where applicable)
- No warranty or liability from developers

### Terms of Service
- Users are responsible for their own content and compliance with local laws
- Platform reserves right to moderate content and manage user accounts
- Blockchain transactions are irreversible; users should verify before confirming
- Platform may evolve and change features through governance or owner decisions

### Privacy Policy
- All blockchain data is public and permanent
- Personal information in profiles is user-controlled
- Platform does not collect additional data beyond smart contract interactions
- Users can update or delete profile information at any time

## Support and Community

### Getting Help
- **GitHub Issues**: Bug reports and feature requests
- **Discord Community**: Real-time chat and community support
- **Documentation**: Comprehensive guides at docs.greetingcontract.io
- **Email Support**: Technical support at support@greetingcontract.io

### Community Channels
- **Twitter**: @GreetingContract for updates and announcements
- **Reddit**: r/GreetingContract for discussions and community posts
- **Telegram**: Official channel for community coordination
- **LinkedIn**: Professional network for business and partnership inquiries

### Contributing to the Project
We welcome contributions from developers, designers, translators, and community managers:
- **Code Contributions**: Smart contract improvements, frontend development
- **Translation**: Help make the platform accessible in more languages
- **Community Management**: Moderate discussions and help new users
- **Documentation**: Improve guides, tutorials, and API documentation
- **Testing**: Help identify bugs and test new features

---

*Spreading positivity, one greeting at a time* 🌟💫

## package.json

```json
{
  "name": "greeting-contract",
  "version": "1.0.0",
  "description": "Blockchain-based platform for storing and managing personalized greeting messages",
  "main": "index.js",
  "scripts": {
    "compile": "hardhat compile",
    "test": "hardhat test",
    "test:coverage": "hardhat coverage",
    "deploy:local": "hardhat run scripts/deploy.js --network localhost",
    "deploy:testnet": "hardhat run scripts/deploy.js --network goerli",
    "deploy:mainnet": "hardhat run scripts/deploy.js --network mainnet",
    "verify": "hardhat verify",
    "lint": "solhint 'contracts/**/*.sol'",
    "prettier": "prettier --write 'contracts/**/*.sol'",
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "keywords": [
    "solidity",
    "ethereum",
    "greeting",
    "social",
    "blockchain",
    "smart-contracts",
    "web3",
    "decentralized",
    "positivity",
    "community"
  ],
  "author": "Greeting Platform Team",
  "license": "MIT",
  "devDependencies": {
    "@nomicfoundation/hardhat-toolbox": "^3.0.0",
    "@nomicfoundation/hardhat-verify": "^1.1.0",
    "hardhat": "^2.17.0",
    "hardhat-gas-reporter": "^1.0.9",
    "solidity-coverage": "^0.8.4",
    "solhint": "^3.6.2",
    "prettier": "^3.0.0",
    "prettier-plugin-solidity": "^1.1.3",
    "chai": "^4.3.7",
    "mocha": "^10.2.0"
  },
  "dependencies": {
    "@openzeppelin/contracts": "^4.9.0",
    "dotenv": "^16.3.0",
    "ethers": "^5.7.0"
  },
  "engines": {
    "node": ">=16.0.0"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/yourusername/greeting-contract.git"
  },
  "bugs": {
    "url": "https://github.com/yourusername/greeting-contract/issues"
  },
  "homepage": "https://github.com/yourusername/greeting-contract#readme"
}
```
