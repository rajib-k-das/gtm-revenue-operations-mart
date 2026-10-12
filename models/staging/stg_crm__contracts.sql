-- 12-month subscription contracts created by won deals. A renewal contract points to the contract it renews.
select
    trim(Id)                                        as contract_id,
    trim(AccountId)                                 as account_id,
    trim(OpportunityId)                             as opportunity_id,
    trim(ContractType)                              as contract_type,
    cast(StartDate as date)                         as start_date,
    cast(EndDate as date)                           as end_date,
    cast(AnnualRecurringRevenue as decimal(14, 2))  as arr,
    nullif(trim(RenewedContractId), '')             as renewed_contract_id
from {{ source('crm', 'contracts') }}
