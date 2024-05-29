select
    c_custkey as customer_id,
    c_name,
    c_address

 from {{ source('tpch', 'customer') }}