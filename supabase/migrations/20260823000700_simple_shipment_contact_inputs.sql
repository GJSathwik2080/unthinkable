-- Keep shipment entry simple: a name and address only need to be present.
-- Phone numbers remain normalized and validated by the application as 10 digits.
alter table public.order_addresses
  drop constraint if exists order_addresses_recipient_name_check,
  drop constraint if exists order_addresses_address_line_1_check;

alter table public.order_addresses
  add constraint order_addresses_recipient_name_check check (char_length(trim(recipient_name)) >= 1),
  add constraint order_addresses_address_line_1_check check (char_length(trim(address_line_1)) >= 1);
