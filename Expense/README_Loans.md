# Loan Management Feature

## Overview
The loan management feature allows users to track both loans taken and personal loans given, with automatic interest calculation based on ROI (Rate of Interest) and dates.

## Features

### 1. Loan Types
- **Loans Taken**: Money borrowed from banks, institutions, or individuals
- **Personal Loans Given**: Money lent to friends, family, or others

### 2. Interest Calculation
- **Annual Interest Rate**: Interest is calculated based on annual percentage rate
- **Daily Calculation**: Interest accrues daily based on the outstanding amount
- **Automatic Updates**: Interest is automatically calculated when the app is opened
- **Manual Calculation**: Users can manually trigger interest calculation

### 3. Loan Details
Each loan includes:
- Principal amount
- Interest rate (annual percentage)
- Loan start date
- Last interest calculation date
- Outstanding amount
- Accrued interest
- Notes and additional information

## How Interest Calculation Works

### Formula
```
Interest = Outstanding Amount × (Annual Rate / 100) × (Days / 365)
```

### Example
- Principal: ₹100,000
- Annual Rate: 12%
- Days since last calculation: 30
- Interest = ₹100,000 × (12/100) × (30/365) = ₹986.30

## Usage

### Adding a New Loan
1. Go to the "Loans" tab
2. Tap the "+" button or "Add New Loan"
3. Choose loan type (Taken or Given)
4. Enter loan details:
   - Loan name
   - Principal amount
   - Interest rate (annual percentage)
   - Loan date
   - Notes (optional)
5. Save the loan

### Viewing Loan Details
1. Tap on any loan in the Loans tab
2. View comprehensive loan information including:
   - Current outstanding amount
   - Accrued interest
   - Principal amount
   - Interest rate
   - Days since last calculation

### Making Loan Payments
1. For loans taken, use the "Make Payment" button
2. Select source account and payment amount
3. Payment reduces the outstanding amount

### Calculating Interest
- **Automatic**: Interest is calculated when the app opens
- **Manual**: Use "Calculate Interest" button to manually apply interest
- **Bulk**: Use "Calculate All Interest" to update all loans at once

## Data Storage

### Core Data Structure
- **CDAccount**: Stores loan account information
- **CDTransaction**: Stores interest transactions and payments
- **Metadata**: Stores loan-specific details like rates and dates

### Metadata Fields
- `principalAmount`: Original loan amount
- `interestRate`: Annual interest rate
- `loanDate`: When the loan was taken/given
- `lastInterestCalculationDate`: Last time interest was calculated
- `borrowerName`: For personal loans given
- `notes`: Additional information

## Technical Implementation

### Key Components
1. **LoanManager**: Handles interest calculations and loan operations
2. **LoanDetails**: Data structure for loan information
3. **LoanDetailsView**: Detailed loan view with actions
4. **AddLoanView**: Create new loans
5. **LoansView**: Main loans dashboard

### Interest Calculation Logic
```swift
func calculateInterestForLoan(_ account: CDAccount) -> Double {
    let days = Calendar.current.dateComponents([.day], from: lastCalculationDate, to: Date()).day ?? 0
    let years = Double(days) / 365.0
    return outstandingAmount * (interestRate / 100.0) * years
}
```

## Benefits
1. **Accurate Tracking**: Real-time interest calculation
2. **Flexible**: Supports both loans taken and given
3. **User-Friendly**: Simple interface with clear information
4. **Automatic**: Reduces manual work with automatic calculations
5. **Comprehensive**: Complete loan history and transaction tracking

## Future Enhancements
- EMI calculation and tracking
- Multiple interest rate periods
- Loan comparison tools
- Export loan statements
- Payment reminders
- Loan amortization schedules 