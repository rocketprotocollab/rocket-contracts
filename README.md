# Rocket Protocol

[Audit report by Cyberscope](https://github.com/cyberscope-io/audits/blob/main/11-rocket/audit.pdf)

Rocket Protocol is a fair launch protocol for MEME tokens.

Tokens created using Rocket Protocol come with FairMint features and offer the following advantages:

- Fair token system: 50% FairMint, 50% added to LP.
- Easy to participate, players only need to transfer ETH to token address, no DAPP required.
- Players can self refund at any time before minting ends. 
- Fair for everyone, no rats, no worries of bots sniping tokens. 
- Safe funds: Funds are securely held in the token contract, with no third-party custody.
- No rug pulls: Once added to DEX, LP will automatically be transferred to black hole for burning.

## >> Rocket Protocol Rules <<

### 1. When creating token, some important attributes need to be defined:

(1) FairMint deadline.
(2) LP Maximum Limit (LPML):

If the amount of ETH raised is less than the LPML, the actual amount of ETH raised will be added to the LP.
If the amount of ETH raised exceeds the LPML, ETH equal to the LPML will be added to the LP, 
and the remaining ETH will be refunded to each participant proportionally.

### 2. How to participate in FairMint?
Players can simply send ETH to the token contract address.
Minimum participation amount per player is 0.0001 ETH, with no maximum limit.
Before LP added, send 0.0002 ETH to the token address for refund, which will deduct 6% protocol service fee.

### 3. How do players claim tokens?
After LP added, send 0.0001 ETH to the token address to claim their tokens.
Number of tokens you receive = 50% of token total supply * Your ETH contribution / Total ETH raised.

### 4. How to add LP and initiate trading?
After the FairMint deadline, anyone can send 0.0005 ETH to token address to add LP, and the LP will automatically be transferred to a black hole for burning.

### 5. If funds raised exceeds LPML, how to get ETH refund?
After LP added, send 0.0002 ETH to the token address to claim remaining ETH.
This process incurs no fees, and the 0.0002 ETH sent will also be refunded.

## Install 

1. Install OpenZeppelin Libs:

```
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2
```

2. Run tests

```
forge test
```


