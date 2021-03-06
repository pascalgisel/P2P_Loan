//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./helper/BNum.sol";

contract P2PLending is ERC721("Embark Loan", "EMK"), BNum() {

    

    // using ABDKMath64x64 for int;
    using SafeMath for uint256;
    using SafeMath for uint;



    struct Loan{
        uint loanId;   //NFT Id
        address borrower; // Address of borrower
        uint max_interest_rate;
        uint principal_amount;
        uint principal_balance;
        uint amount_paid;
        uint startTime;
        uint yearly_payments;
        uint total_payments;
        uint total_annuity;
        uint repaymentsMade;
        Status status;
        bytes32 currency;
        address[] investors_index;
    }

    struct Investor{
        address investor_address;
        uint investor_principal;
        uint interest;
        uint investor_annuity;
        bool paid_in;
        bool exists;
    }

    //Struct for supported tokens as payment
    struct Token {
        bytes32 ticker;
        address tokenAddress;
    }

    enum Status{
        Application,
        PayIn,
        Loan,
        Done
    }

    event newLoanStarted (uint256 indexed _id, address indexed _borrower);

    //Global counters, always increment, used as Id for NFT
    uint numLoans;
    address admin;

    mapping(uint => Loan) private loans;
    mapping (address => Investor) private investors;

    mapping (bytes32 => Token) private tokens;
    bytes32[] tokenList;

    mapping(address => mapping(bytes32 => uint)) public balances;

    constructor () {
        admin = msg.sender;
        numLoans = 0;
    }

    function addToken(
        bytes32 ticker,
        address tokenAddress)
        onlyAdmin()
        external {
        tokens[ticker] = Token(ticker, tokenAddress);
        tokenList.push(ticker);
    }

  
     function divisionTest(uint256 _a, uint256 _b) public pure returns (uint){
       uint result = bdiv(_a, _b);

       return result;
    }

    
    function calculateInterest(uint256 interest, uint256 payments, uint256 yearlyPayments, uint256 principal) public pure returns (uint256){
        uint256 rate = 0;
        uint256 one = bpow(10,18);
        uint256[] memory s = new uint256[](4);
        uint i_period = bdiv(interest, yearlyPayments);
        uint q_period = badd(i_period, one);
        


        s[0] = bpow(q_period, payments);
        s[1] = bmul(s[0], i_period);
        s[2] = bsub(s[0],one);

        s[3] = bdiv(s[1],s[2]);
        rate = bmul(s[3], principal);
        return rate;
    }


    function createLoanApplication(uint _max_interest_rate, uint _credit_amount, uint _yearly_payments, uint _total_payments, bytes32 _currency) public returns(uint256 loanId){ 
        require(tokens[_currency].tokenAddress != address(0));
        uint256 newId = numLoans.add(1);
        
        _mint(msg.sender, newId);
        Loan memory _loan;
        _loan.loanId = newId;
        _loan.borrower = msg.sender;
        _loan.max_interest_rate = _max_interest_rate;
        _loan.principal_amount = _credit_amount;
        _loan.principal_balance =   _credit_amount;
        _loan.amount_paid =   0;
        _loan.startTime =  0;
        _loan.yearly_payments =  _yearly_payments;
        _loan.total_payments = _total_payments;
        _loan.status = Status.Application;
        _loan.currency = _currency;
        _loan.repaymentsMade = 0;

        loans[newId] = _loan;
        numLoans = newId;
        return newId;
    }


    function writeLoanParams(uint _id, Investor[] memory _investors) public {
        require(loans[_id].loanId != 0, "LoanId doesnt exist!");
        
        //write Investors into Mapping
        for(uint i = 0; i < _investors.length; i++){
            address tempAd = _investors[i].investor_address;
            loans[_id].investors_index.push(tempAd);
            investors[tempAd] = _investors[i]; 
        }

        loans[_id].status = Status.PayIn;
    }

    function payIn (uint _id, uint256 amount) public {
        Investor memory inv = investors[msg.sender];
        require(inv.exists == true, "investor doesnt exist");
        require(inv.paid_in == false, "already paid in");
        require(inv.investor_principal == amount*10**18, "wrong amount");
        address borrower = loans[_id].borrower;
        bytes32 ticker = loans[_id].currency;
        //transferFrom
        IERC20(tokens[ticker].tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        investors[msg.sender].investor_annuity = calculateInterest(inv.interest, loans[_id].total_payments, loans[_id].yearly_payments, inv.investor_principal);


        balances[borrower][ticker] = balances[borrower][ticker].add(amount);
        investors[msg.sender].paid_in = true;
    }

    function checkAndStartLoan(uint256 _id) public returns (bool){
        address[] memory ia = loans[_id].investors_index;
        for(uint i = 0; i < ia.length; i++){
            if(investors[ia[i]].paid_in == false){
                return false;
            }
        }

        uint total = 0;
        for(uint j = 0; j < ia.length; j++){
           total = total.add(investors[ia[j]].investor_annuity);
        }


        loans[_id].total_annuity = total;
        loans[_id].status = Status.Loan;
        loans[_id].startTime = block.timestamp;
        emit newLoanStarted(_id, loans[_id].borrower);
        return true;
    }


    function repayLoan(uint _id, uint amount) public {
        require(msg.sender == loans[_id].borrower, "only borrower can repay");
        require(loans[_id].status == Status.Loan, "This loan is not active");
        require(btoi(bfloor(loans[_id].total_annuity)) == amount, "Wrong amount");

        IERC20(tokens[loans[_id].currency].tokenAddress).transferFrom(
            loans[_id].borrower,
            address(this),
            amount
        );

        address[] memory ia = loans[_id].investors_index;

        uint paybackAmount = 0;
        for(uint i = 0; i < ia.length; i++){
            paybackAmount = btoi(bfloor(investors[ia[i]].investor_annuity));

                IERC20(tokens[loans[_id].currency].tokenAddress).transfer(
                    investors[ia[i]].investor_address,
                    paybackAmount
                );
            }

        loans[_id].repaymentsMade = loans[_id].repaymentsMade.add(1);
        if(loans[_id].repaymentsMade == btoi(loans[_id].total_payments)){
            loans[_id].status = Status.Done;
        }
    }

    function getLoan(uint256 _id) public view returns (Loan memory){
       return loans[_id];
    }

    function getStatus(uint256 _id) public view returns (Status){
        return loans[_id].status;
    }

    function getInvestor(address _investor_address) public view returns (Investor memory){
        return investors[_investor_address];
    }

    function getBalance(address add, bytes32 ticker) public view returns (uint256){
        return balances[add][ticker];
    }

     modifier onlyAdmin() {
        require(msg.sender == admin, 'only admin');
        _;
    }
    
}