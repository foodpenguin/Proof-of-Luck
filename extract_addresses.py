import json

try:
    with open('packages/contracts/broadcast/DeployFork.s.sol/31337/run-latest.json', 'r') as f:
        data = json.load(f)
        for t in data['transactions']:
            if t['transactionType'] == 'CREATE':
                print(f"{t.get('contractName')}: {t.get('contractAddress')}")
except Exception as e:
    print(f"Error: {e}")
