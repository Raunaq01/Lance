// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Freelance Platform
 * @dev A smart contract for managing freelance projects with escrow functionality
 */
contract Lance {
    
    // Struct to represent a freelance project
    struct Project {
        uint256 id;
        address client;
        address freelancer;
        string title;
        string description;
        uint256 budget;
        uint256 deadline;
        ProjectStatus status;
        bool fundsDeposited;
        uint256 createdAt;
    }
    
    // Enum for project status
    enum ProjectStatus {
        Open,           // Project is open for bids
        Assigned,       // Freelancer assigned, work in progress
        Submitted,      // Work submitted by freelancer
        Completed,      // Project completed and funds released
        Disputed,       // Project is in dispute
        Cancelled       // Project cancelled
    }
    
    // State variables
    uint256 private nextProjectId;
    uint256 public platformFeePercentage = 5; // 5% platform fee
    address public owner;
    
    // Mappings
    mapping(uint256 => Project) public projects;
    mapping(address => uint256[]) public clientProjects;
    mapping(address => uint256[]) public freelancerProjects;
    mapping(uint256 => address[]) public projectBids; // projectId => bidder addresses
    
    // Events
    event ProjectCreated(uint256 indexed projectId, address indexed client, string title, uint256 budget);
    event BidSubmitted(uint256 indexed projectId, address indexed freelancer);
    event FreelancerAssigned(uint256 indexed projectId, address indexed freelancer);
    event WorkSubmitted(uint256 indexed projectId, address indexed freelancer);
    event ProjectCompleted(uint256 indexed projectId, address indexed freelancer, uint256 amount);
    event ProjectCancelled(uint256 indexed projectId, address indexed client);
    event DisputeRaised(uint256 indexed projectId, address indexed initiator);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyClient(uint256 _projectId) {
        require(msg.sender == projects[_projectId].client, "Only client can call this function");
        _;
    }
    
    modifier onlyFreelancer(uint256 _projectId) {
        require(msg.sender == projects[_projectId].freelancer, "Only assigned freelancer can call this function");
        _;
    }
    
    modifier projectExists(uint256 _projectId) {
        require(_projectId < nextProjectId, "Project does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        nextProjectId = 1;
    }
    
    /**
     * @dev Create a new freelance project
     * @param _title Project title
     * @param _description Project description
     * @param _deadline Project deadline (timestamp)
     */
    function createProject(
        string memory _title,
        string memory _description,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Budget must be greater than 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        
        uint256 projectId = nextProjectId++;
        
        projects[projectId] = Project({
            id: projectId,
            client: msg.sender,
            freelancer: address(0),
            title: _title,
            description: _description,
            budget: msg.value,
            deadline: _deadline,
            status: ProjectStatus.Open,
            fundsDeposited: true,
            createdAt: block.timestamp
        });
        
        clientProjects[msg.sender].push(projectId);
        
        emit ProjectCreated(projectId, msg.sender, _title, msg.value);
    }
    
    /**
     * @dev Submit a bid for an open project
     * @param _projectId ID of the project to bid on
     */
    function submitBid(uint256 _projectId) external projectExists(_projectId) {
        Project memory project = projects[_projectId];
        require(project.status == ProjectStatus.Open, "Project is not open for bids");
        require(msg.sender != project.client, "Client cannot bid on their own project");
        require(block.timestamp < project.deadline, "Project deadline has passed");
        
        // Check if freelancer has already bid
        address[] memory bids = projectBids[_projectId];
        for (uint i = 0; i < bids.length; i++) {
            require(bids[i] != msg.sender, "You have already bid on this project");
        }
        
        projectBids[_projectId].push(msg.sender);
        
        emit BidSubmitted(_projectId, msg.sender);
    }
    
    /**
     * @dev Assign a freelancer to the project
     * @param _projectId ID of the project
     * @param _freelancer Address of the chosen freelancer
     */
    function assignFreelancer(uint256 _projectId, address _freelancer) 
        external 
        projectExists(_projectId) 
        onlyClient(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Open, "Project is not open");
        require(_freelancer != address(0), "Invalid freelancer address");
        require(_freelancer != project.client, "Client cannot be the freelancer");
        
        // Verify that the freelancer has bid on this project
        bool validBidder = false;
        address[] memory bids = projectBids[_projectId];
        for (uint i = 0; i < bids.length; i++) {
            if (bids[i] == _freelancer) {
                validBidder = true;
                break;
            }
        }
        require(validBidder, "Freelancer must have submitted a bid");
        
        project.freelancer = _freelancer;
        project.status = ProjectStatus.Assigned;
        
        freelancerProjects[_freelancer].push(_projectId);
        
        emit FreelancerAssigned(_projectId, _freelancer);
    }
    
    /**
     * @dev Submit completed work (called by freelancer)
     * @param _projectId ID of the project
     */
    function submitWork(uint256 _projectId) 
        external 
        projectExists(_projectId) 
        onlyFreelancer(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Assigned, "Project is not in assigned status");
        require(block.timestamp <= project.deadline, "Project deadline has passed");
        
        project.status = ProjectStatus.Submitted;
        
        emit WorkSubmitted(_projectId, msg.sender);
    }
    
    /**
     * @dev Complete project and release funds (called by client)
     * @param _projectId ID of the project
     */
    function completeProject(uint256 _projectId) 
        external 
        projectExists(_projectId) 
        onlyClient(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Submitted, "Work has not been submitted");
        require(project.fundsDeposited, "Funds not deposited");
        
        uint256 platformFee = (project.budget * platformFeePercentage) / 100;
        uint256 freelancerPayment = project.budget - platformFee;
        
        project.status = ProjectStatus.Completed;
        project.fundsDeposited = false;
        
        // Transfer funds
        payable(project.freelancer).transfer(freelancerPayment);
        payable(owner).transfer(platformFee);
        
        emit ProjectCompleted(_projectId, project.freelancer, freelancerPayment);
    }
    
    // Additional utility functions
    
    /**
     * @dev Get project details
     * @param _projectId ID of the project
     */
    function getProject(uint256 _projectId) 
        external 
        view 
        projectExists(_projectId) 
        returns (Project memory) 
    {
        return projects[_projectId];
    }
    
    /**
     * @dev Get all bids for a project
     * @param _projectId ID of the project
     */
    function getProjectBids(uint256 _projectId) 
        external 
        view 
        projectExists(_projectId) 
        returns (address[] memory) 
    {
        return projectBids[_projectId];
    }
    
    /**
     * @dev Get projects created by a client
     * @param _client Address of the client
     */
    function getClientProjects(address _client) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return clientProjects[_client];
    }
    
    /**
     * @dev Get projects assigned to a freelancer
     * @param _freelancer Address of the freelancer
     */
    function getFreelancerProjects(address _freelancer) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return freelancerProjects[_freelancer];
    }
    
    /**
     * @dev Get total number of projects
     */
    function getTotalProjects() external view returns (uint256) {
        return nextProjectId - 1;
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFeePercentage New fee percentage
     */
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }
    
    /**
     * @dev Cancel project and refund client (only client, only if not assigned)
     * @param _projectId ID of the project
     */
    function cancelProject(uint256 _projectId) 
        external 
        projectExists(_projectId) 
        onlyClient(_projectId) 
    {
        Project storage project = projects[_projectId];
        require(project.status == ProjectStatus.Open, "Can only cancel open projects");
        require(project.fundsDeposited, "Funds already withdrawn");
        
        project.status = ProjectStatus.Cancelled;
        project.fundsDeposited = false;
        
        // Refund the client
        payable(project.client).transfer(project.budget);
        
        emit ProjectCancelled(_projectId, msg.sender);
    }
}
