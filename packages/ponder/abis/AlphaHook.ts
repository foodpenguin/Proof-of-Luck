export const AlphaHookABI = [
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "drawId", "type": "uint256" },
      { "indexed": false, "internalType": "uint256", "name": "requestId", "type": "uint256" }
    ],
    "name": "DrawRequested",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "drawId", "type": "uint256" },
      { "indexed": false, "internalType": "uint256", "name": "winnerTokenId", "type": "uint256" },
      { "indexed": false, "internalType": "uint256", "name": "randomWord", "type": "uint256" }
    ],
    "name": "DrawCompleted",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "uint256", "name": "tokenId", "type": "uint256" },
      { "indexed": false, "internalType": "uint256", "name": "newWeight", "type": "uint256" }
    ],
    "name": "TicketEvolved",
    "type": "event"
  }
] as const;
