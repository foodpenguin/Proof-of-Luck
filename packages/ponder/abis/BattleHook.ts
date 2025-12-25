export const BattleHookABI = [
  {
    "type": "constructor",
    "inputs": [
      { "name": "_masterVault", "type": "address", "internalType": "address" },
      { "name": "_vrfCoordinator", "type": "address", "internalType": "address" },
      { "name": "_subscriptionId", "type": "uint64", "internalType": "uint64" },
      { "name": "_keyHash", "type": "bytes32", "internalType": "bytes32" }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "checkUpkeep",
    "inputs": [{ "name": "", "type": "bytes", "internalType": "bytes" }],
    "outputs": [
      { "name": "upkeepNeeded", "type": "bool", "internalType": "bool" },
      { "name": "performData", "type": "bytes", "internalType": "bytes" }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "forceStartGame",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getGameStatus",
    "inputs": [],
    "outputs": [
      { "name": "roundId", "type": "uint256", "internalType": "uint256" },
      { "name": "isActive", "type": "bool", "internalType": "bool" },
      { "name": "startTime", "type": "uint256", "internalType": "uint256" },
      { "name": "playerCount", "type": "uint256", "internalType": "uint256" },
      { "name": "zoneRadius", "type": "uint256", "internalType": "uint256" },
      { "name": "center", "type": "tuple", "internalType": "struct BattleHook.Point", "components": [
        { "name": "x", "type": "int256", "internalType": "int256" },
        { "name": "y", "type": "int256", "internalType": "int256" }
      ]}
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getPlayerLocation",
    "inputs": [
      { "name": "roundId", "type": "uint256", "internalType": "uint256" },
      { "name": "player", "type": "address", "internalType": "address" }
    ],
    "outputs": [
      { "name": "x", "type": "int256", "internalType": "int256" },
      { "name": "y", "type": "int256", "internalType": "int256" },
      { "name": "alive", "type": "bool", "internalType": "bool" }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "isWinner",
    "inputs": [
      { "name": "player", "type": "address", "internalType": "address" }
    ],
    "outputs": [
      { "name": "", "type": "bool", "internalType": "bool" }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "onDeposit",
    "inputs": [
      { "name": "depositor", "type": "address", "internalType": "address" },
      { "name": "amount", "type": "uint256", "internalType": "uint256" },
      { "name": "shares", "type": "uint256", "internalType": "uint256" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "performUpkeep",
    "inputs": [{ "name": "performData", "type": "bytes", "internalType": "bytes" }],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "rawFulfillRandomWords",
    "inputs": [
      { "name": "requestId", "type": "uint256", "internalType": "uint256" },
      { "name": "randomWords", "type": "uint256[]", "internalType": "uint256[]" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "GameStarted",
    "inputs": [
      { "name": "roundId", "type": "uint256", "indexed": true, "internalType": "uint256" },
      { "name": "startTime", "type": "uint256", "indexed": false, "internalType": "uint256" },
      { "name": "playerCount", "type": "uint256", "indexed": false, "internalType": "uint256" }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PlayerEliminated",
    "inputs": [
      { "name": "roundId", "type": "uint256", "indexed": true, "internalType": "uint256" },
      { "name": "player", "type": "address", "indexed": true, "internalType": "address" },
      { "name": "reason", "type": "string", "indexed": false, "internalType": "string" }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PlayerMoved",
    "inputs": [
      { "name": "roundId", "type": "uint256", "indexed": true, "internalType": "uint256" },
      { "name": "player", "type": "address", "indexed": true, "internalType": "address" },
      { "name": "x", "type": "int256", "indexed": false, "internalType": "int256" },
      { "name": "y", "type": "int256", "indexed": false, "internalType": "int256" }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "WinnerDeclared",
    "inputs": [
      { "name": "roundId", "type": "uint256", "indexed": true, "internalType": "uint256" },
      { "name": "winner", "type": "address", "indexed": true, "internalType": "address" },
      { "name": "prize", "type": "uint256", "indexed": false, "internalType": "uint256" }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "ZoneShrunk",
    "inputs": [
      { "name": "roundId", "type": "uint256", "indexed": true, "internalType": "uint256" },
      { "name": "newRadius", "type": "uint256", "indexed": false, "internalType": "uint256" },
      { "name": "centerX", "type": "int256", "indexed": false, "internalType": "int256" },
      { "name": "centerY", "type": "int256", "indexed": false, "internalType": "int256" }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "OnlyMasterVault",
    "inputs": []
  },
  {
    "type": "error",
    "name": "GameAlreadyActive",
    "inputs": []
  },
  {
    "type": "error",
    "name": "GameNotActive",
    "inputs": []
  },
  {
    "type": "error",
    "name": "PlayerAlreadyJoined",
    "inputs": []
  },
  {
    "type": "error",
    "name": "PlayerNotAlive",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidMove",
    "inputs": []
  }
] as const;
