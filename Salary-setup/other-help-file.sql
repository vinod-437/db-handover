-- Statutory Components
select * from mst_otherduction where  
(customeraccountid=3088 or customeraccountid is null) 
and active='Y'


select * from mst_tp_business_setups where tp_account_id=3088 order by 1  desc

select * from mastersalarystructure limit 10;