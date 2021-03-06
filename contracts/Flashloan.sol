pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "@studydefi/money-legos/dydx/contracts/DydxFlashloanBase.sol";
import "@studydefi/money-legos/dydx/contracts/ICallee.sol";
import { KyberNetworkProxy as IKyberNetworkProxy } from '@studydefi/money-legos/kyber/contracts/KyberNetworkProxy.sol';

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './IUniswapV2Router02.sol';
import './IWeth.sol';
//flashloan inherits from the 2 other contracts  ICallee , DydxFlashloanBase
contract Flashloan is ICallee, DydxFlashloanBase {
  //directionof the logic.....start
    enum Direction { KyberToUniswap, UniswapToKyber } 
    struct ArbInfo {
        Direction direction;///in the function initiateFlashloan
        uint repayAmount;
    }
  ///........................end
    event NewArbitrage (
      Direction direction,
      uint profit,
      uint date
    );

    IKyberNetworkProxy kyber;
    IUniswapV2Router02 uniswap;
    IWeth weth;
    IERC20 dai;             //interfaces //(check 23.)
    address beneficiary;
    address constant KYBER_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;//allows to save some gas

    constructor(
        address kyberAddress,
        address uniswapAddress,
        address wethAddress,    //(constructor ;;;lec 23)
        address daiAddress,
        address beneficiaryAddress
    ) public {
      kyber = IKyberNetworkProxy(kyberAddress);
      uniswap = IUniswapV2Router02(uniswapAddress);
      weth = IWeth(wethAddress);
      dai = IERC20(daiAddress);
      beneficiary = beneficiaryAddress;
    }

    // This is the function that will be called postLoan
    // i.e. Encode the logic to handle your flashloaned funds here
    //step 1 .........................................................
    function callFunction(
        address sender,
        Account.Info memory account,
        bytes memory data
        //.....................................................................
    ) public {
        ArbInfo memory arbInfo = abi.decode(data, (ArbInfo));//(check 23.)
      
        
        uint256 balanceDai = dai.balanceOf(address(this));
        //.....................................................................
//.......................//.....................................//.......................................................check 24(start)
        if(arbInfo.direction == Direction.KyberToUniswap) {//the direction is KyberToUniswap
          //Buy ETH on Kyber
          dai.approve(address(kyber), balanceDai); 
          (uint expectedRate, ) = kyber.getExpectedRate(
            dai, 
            IERC20(KYBER_ETH_ADDRESS), //only in case of Kyberuniswap
            balanceDai
          );
          kyber.swapTokenToEther(dai, balanceDai, expectedRate);

          //Sell ETH on Uniswap
          address[] memory path = new address[](2);
          path[0] = address(weth);
          path[1] = address(dai);
          uint[] memory minOuts = uniswap.getAmountsOut(address(this).balance, path); f
          uniswap.swapExactETHForTokens.value(address(this).balance)(
            minOuts[1], //...where swapping will occurr
            path, 
            address(this), //who is going to get the tokens
            now            //time of the swap
          );
//.......................//.....................................//.......................................................check 24(end)
        } 
//.......................///check 25(start)        
         else {
          //Buy ETH on Uniswap
          dai.approve(address(uniswap), balanceDai); 
          address[] memory path = new address[](2);
          path[0] = address(dai);
          path[1] = address(weth);
          uint[] memory minOuts = uniswap.getAmountsOut(balanceDai, path); 
          uniswap.swapExactTokensForETH(
            balanceDai, 
            minOuts[1], 
            path, 
            address(this), 
            now
          );

          //Sell ETH on Kyber
          (uint expectedRate, ) = kyber.getExpectedRate(
            IERC20(KYBER_ETH_ADDRESS), 
            dai, 
            address(this).balance
          );
          kyber.swapEtherToToken.value(address(this).balance)(
            dai, 
            expectedRate
          );
        }
//.......................///check 25(end)        

        require(
            dai.balanceOf(address(this)) >= arbInfo.repayAmount,
            "Not enough funds to repay dydx loan!"
        );
//.......................///check 26(start)withdraw the funds from the contract
        uint profit = dai.balanceOf(address(this)) - arbInfo.repayAmount; 
        dai.transfer(beneficiary, profit);
        emit NewArbitrage(arbInfo.direction, profit, now);//check line 20
    }
//.......................///check 26(end)
    function initiateFlashloan(
      address _solo, 
      address _token, 
      uint256 _amount, 
      Direction _direction)
        external
    {
        ISoloMargin solo = ISoloMargin(_solo);

        // Get marketId from token address
        uint256 marketId = _getMarketIdFromTokenAddress(_solo, _token);

        // Calculate repay amount (_amount + (2 wei))
        // Approve transfer from
        uint256 repayAmount = _getRepaymentAmountInternal(_amount);
        IERC20(_token).approve(_solo, repayAmount);

        // 1. Withdraw $
        // 2. Call callFunction(...)
        // 3. Deposit back $
        Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](3);

        operations[0] = _getWithdrawAction(marketId, _amount);
        operations[1] = _getCallAction(
            // Encode MyCustomData for callFunction
            abi.encode(ArbInfo({direction: _direction, repayAmount: repayAmount}))
        );
        operations[2] = _getDepositAction(marketId, repayAmount);

        Account.Info[] memory accountInfos = new Account.Info[](1);
        accountInfos[0] = _getAccountInfo();

        solo.operate(accountInfos, operations);
    }

    function() external payable {}//fallback function whose body is empty,,,(check 24.)
}
