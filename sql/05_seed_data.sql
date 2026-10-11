-- =====================================================================
-- File 05: Sample data
-- Reference data is inserted directly. Orders, payments and shipments are
-- created THROUGH the stored procedures so the stock figures, order totals
-- and automatic purchase orders are produced by the database logic itself.
-- =====================================================================

INSERT INTO customer (name, email, phone, address, city, registered_date, status) VALUES
 ('Aarav Reddy',     'aarav.reddy@mail.com',   '9876500001', '12 Jubilee Hills',      'Hyderabad', '2026-01-10', 'ACTIVE'),
 ('Priya Nair',      'priya.nair@mail.com',    '9876500002', '45 Anna Nagar',         'Chennai',   '2026-01-22', 'ACTIVE'),
 ('Rohan Mehta',     'rohan.mehta@mail.com',   '9876500003', '8 Bandra West',         'Mumbai',    '2026-02-05', 'ACTIVE'),
 ('Sneha Kapoor',    'sneha.kapoor@mail.com',  '9876500004', '21 Connaught Place',    'Delhi',     '2026-02-18', 'ACTIVE'),
 ('Vikram Singh',    'vikram.singh@mail.com',  '9876500005', '77 MG Road',            'Bengaluru', '2026-03-03', 'ACTIVE'),
 ('Ananya Iyer',     'ananya.iyer@mail.com',   '9876500006', '5 T Nagar',             'Chennai',   '2026-03-15', 'ACTIVE'),
 ('Karthik Rao',     'karthik.rao@mail.com',   '9876500007', '33 Banjara Hills',      'Hyderabad', '2026-04-01', 'ACTIVE'),
 ('Meera Joshi',     'meera.joshi@mail.com',   '9876500008', '14 Koregaon Park',      'Pune',      '2026-04-20', 'ACTIVE'),
 ('Arjun Das',       'arjun.das@mail.com',     '9876500009', '9 Salt Lake',           'Kolkata',   '2026-05-11', 'ACTIVE'),
 ('Divya Menon',     'divya.menon@mail.com',   '9876500010', '60 Marine Drive',       'Kochi',     '2026-05-30', 'ACTIVE'),
 ('Nikhil Sharma',   'nikhil.sharma@mail.com', '9876500011', '3 Sector 17',           'Chandigarh','2026-06-14', 'ACTIVE'),
 ('Lakshmi Prasad',  'lakshmi.prasad@mail.com','9876500012', '28 Gandhi Nagar',       'Vijayawada','2026-07-07', 'ACTIVE'),
 ('Ravi Kumar',      'ravi.kumar@mail.com',    '9876500013', '1 Old Town',            'Hyderabad', '2025-11-02', 'INACTIVE');

INSERT INTO supplier (supplier_name, email, phone, lead_time_days) VALUES
 ('TechSource Distributors',  'sales@techsource.example',  '9000000001', 5),
 ('SoundWave Traders',        'orders@soundwave.example',  '9000000002', 7),
 ('UrbanWear Wholesale',      'supply@urbanwear.example',  '9000000003', 8),
 ('HomeNest Supplies',        'sales@homenest.example',    '9000000004', 4),
 ('FitLife Sports Pvt Ltd',   'b2b@fitlife.example',       '9000000005', 6),
 ('PageTurn Books & Stationery','po@pageturn.example',     '9000000006', 3);

INSERT INTO warehouse (warehouse_name, city, capacity) VALUES
 ('Hyderabad Central',   'Hyderabad', 2000),
 ('Chennai Hub',         'Chennai',   1500),
 ('Mumbai Fulfilment',   'Mumbai',    2500),
 ('Delhi North',         'Delhi',     1000);

INSERT INTO product (product_name, category, brand, unit_price, reorder_level, supplier_id) VALUES
 ('Wireless Mouse',            'Electronics', 'Logitech',     799.00, 25, 1),
 ('Mechanical Keyboard',       'Electronics', 'Redragon',    2499.00, 15, 1),
 ('USB-C Hub 7-in-1',          'Electronics', 'Anker',       3299.00, 12, 1),
 ('Bluetooth Headphones',      'Electronics', 'boAt',        1999.00, 20, 2),
 ('Smartphone Stand',          'Accessories', 'Portronics',   399.00, 30, 2),
 ('Power Bank 20000mAh',       'Electronics', 'Mi',          1799.00, 20, 2),
 ('Cotton T-Shirt',            'Fashion',     'Allen Solly',  699.00, 40, 3),
 ('Denim Jeans',               'Fashion',     'Levis',       2199.00, 25, 3),
 ('Running Shoes',             'Footwear',    'Puma',        3999.00, 15, 3),
 ('Backpack 30L',              'Bags',        'Wildcraft',   1599.00, 15, 3),
 ('Stainless Steel Bottle',    'Home',        'Milton',       549.00, 35, 4),
 ('Non-stick Frying Pan',      'Kitchen',     'Prestige',    1299.00, 15, 4),
 ('Mixer Grinder',             'Kitchen',     'Bajaj',       3499.00, 10, 4),
 ('LED Desk Lamp',             'Home',        'Philips',      999.00, 20, 4),
 ('Yoga Mat',                  'Fitness',     'Decathlon',    899.00, 20, 5),
 ('Dumbbell Set 10kg',         'Fitness',     'Cultsport',   2299.00, 10, 5),
 ('Python Programming Book',   'Books',       'O''Reilly',    899.00, 15, 6),
 ('Database System Concepts',  'Books',       'McGraw Hill', 1299.00, 15, 6),
 ('A4 Notebook Pack (5)',      'Stationery',  'Classmate',    349.00, 50, 6),
 ('Gel Pen Box (20)',          'Stationery',  'Reynolds',     249.00, 50, 6);

INSERT INTO inventory (product_id, warehouse_id, quantity_available) VALUES
 (1,1,60),(1,2,40),(1,3,30),
 (2,1,25),(2,3,20),
 (3,2,8),(3,4,7),
 (4,1,35),(4,2,30),(4,4,20),
 (5,1,80),(5,2,60),(5,3,50),(5,4,40),
 (6,2,30),(6,3,25),
 (7,1,100),(7,3,90),(7,4,70),
 (8,1,40),(8,3,35),
 (9,2,20),(9,3,18),
 (10,1,25),(10,4,20),
 (11,1,60),(11,2,50),(11,3,40),
 (12,2,20),(12,4,15),
 (13,1,8),(13,3,6),
 (14,3,30),(14,4,25),
 (15,1,30),(15,2,25),
 (16,2,7),(16,4,5),
 (17,1,20),(17,3,25),
 (18,1,22),(18,2,18),
 (19,1,120),(19,2,100),(19,4,80),
 (20,1,150),(20,3,120);

-- Purchase-order history (already delivered, so inventory above already includes them).
-- Some are on time, some late, one cancelled: feeds the supplier performance report.
INSERT INTO purchase_order
 (product_id, supplier_id, warehouse_id, quantity_ordered, po_date, expected_delivery, actual_delivery, po_status) VALUES
 ( 1,1,1, 60,'2026-06-05','2026-06-10','2026-06-10','RECEIVED'),
 ( 2,1,3, 30,'2026-06-20','2026-06-25','2026-06-27','RECEIVED'),
 ( 3,1,2, 20,'2026-07-02','2026-07-07','2026-07-12','RECEIVED'),
 ( 4,2,1, 40,'2026-06-15','2026-06-22','2026-06-21','RECEIVED'),
 ( 6,2,2, 30,'2026-07-10','2026-07-17','2026-07-19','RECEIVED'),
 ( 7,3,1,150,'2026-06-01','2026-06-09','2026-06-09','RECEIVED'),
 ( 8,3,3, 50,'2026-07-15','2026-07-23','2026-07-30','RECEIVED'),
 (11,4,1, 80,'2026-08-01','2026-08-05','2026-08-04','RECEIVED'),
 (13,4,3, 15,'2026-08-10','2026-08-14','2026-08-18','RECEIVED'),
 (15,5,1, 40,'2026-08-05','2026-08-11','2026-08-11','RECEIVED'),
 (16,5,2, 15,'2026-08-20','2026-08-26','2026-08-29','RECEIVED'),
 (17,6,3, 30,'2026-09-01','2026-09-04','2026-09-03','RECEIVED'),
 (19,6,1,200,'2026-09-05','2026-09-08','2026-09-10','RECEIVED'),
 ( 9,3,2, 25,'2026-09-12','2026-09-20', NULL      ,'CANCELLED');

-- Orders, payments and fulfilment, all driven through the stored procedures.
DO $$
DECLARE
    v  INT;
    r  VARCHAR;
BEGIN
    -- delivered orders --------------------------------------------------------
    CALL place_order( 1,'[{"product_id":1,"quantity":2},{"product_id":5,"quantity":1}]',v,'2026-07-03 10:15');
    CALL record_payment(v,'UPI',true,r);        CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');
    CALL place_order( 2,'[{"product_id":7,"quantity":3},{"product_id":8,"quantity":1}]',v,'2026-07-09 14:40');
    CALL record_payment(v,'CARD',true,r);       CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');
    CALL place_order( 3,'[{"product_id":4,"quantity":1},{"product_id":6,"quantity":1}]',v,'2026-07-15 09:05');
    CALL record_payment(v,'UPI',true,r);        CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');
    CALL place_order( 4,'[{"product_id":11,"quantity":4},{"product_id":12,"quantity":1}]',v,'2026-07-22 17:30');
    CALL record_payment(v,'COD',true,r);        CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');
    CALL place_order( 5,'[{"product_id":17,"quantity":2},{"product_id":18,"quantity":1}]',v,'2026-08-02 11:20');
    CALL record_payment(v,'NETBANKING',true,r); CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');
    CALL place_order( 1,'[{"product_id":2,"quantity":1},{"product_id":3,"quantity":2}]',v,'2026-08-06 19:10');
    CALL record_payment(v,'CARD',true,r);       CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');
    CALL place_order( 6,'[{"product_id":9,"quantity":1},{"product_id":10,"quantity":1}]',v,'2026-08-12 13:00');
    CALL record_payment(v,'UPI',true,r);        CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');
    CALL place_order( 7,'[{"product_id":15,"quantity":2},{"product_id":16,"quantity":1}]',v,'2026-08-18 16:45');
    CALL record_payment(v,'COD',true,r);        CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');
    CALL place_order( 8,'[{"product_id":19,"quantity":5},{"product_id":20,"quantity":10}]',v,'2026-08-25 10:30');
    CALL record_payment(v,'UPI',true,r);        CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');
    CALL place_order( 2,'[{"product_id":13,"quantity":2}]',v,'2026-09-02 12:15');
    CALL record_payment(v,'CARD',true,r);       CALL update_order_status(v,'SHIPPED'); CALL update_order_status(v,'DELIVERED');

    -- shipped, not yet delivered ---------------------------------------------
    CALL place_order( 9,'[{"product_id":4,"quantity":2},{"product_id":5,"quantity":3}]',v,'2026-09-08 15:25');
    CALL record_payment(v,'UPI',true,r);        CALL update_order_status(v,'SHIPPED');
    CALL place_order(10,'[{"product_id":14,"quantity":2},{"product_id":11,"quantity":2}]',v,'2026-09-14 18:50');
    CALL record_payment(v,'NETBANKING',true,r); CALL update_order_status(v,'SHIPPED');

    -- paid / confirmed, waiting to ship (stock sits in RESERVED) ----------------
    CALL place_order( 3,'[{"product_id":1,"quantity":3}]',v,'2026-09-18 10:00');
    CALL record_payment(v,'CARD',true,r);
    CALL place_order( 4,'[{"product_id":7,"quantity":2},{"product_id":20,"quantity":5}]',v,'2026-09-22 20:10');
    CALL record_payment(v,'UPI',true,r);
    CALL place_order(11,'[{"product_id":3,"quantity":4},{"product_id":6,"quantity":2}]',v,'2026-09-27 09:40');
    CALL record_payment(v,'CARD',true,r);
    CALL place_order( 5,'[{"product_id":13,"quantity":3},{"product_id":12,"quantity":2}]',v,'2026-10-01 14:20');
    CALL record_payment(v,'COD',true,r);
    CALL place_order(12,'[{"product_id":16,"quantity":3}]',v,'2026-10-04 11:55');
    CALL record_payment(v,'UPI',true,r);

    -- still PLACED / failed payment / cancelled ---------------------------------
    CALL place_order( 6,'[{"product_id":8,"quantity":2},{"product_id":7,"quantity":1}]',v,'2026-10-06 21:05');
    CALL place_order( 7,'[{"product_id":15,"quantity":1},{"product_id":17,"quantity":1}]',v,'2026-10-08 08:30');
    CALL record_payment(v,'CARD',false,r);                       -- gateway declined: order stays PLACED
    CALL place_order( 9,'[{"product_id":5,"quantity":2}]',v,'2026-10-09 12:00');
    CALL cancel_order(v);
    CALL place_order( 1,'[{"product_id":18,"quantity":1},{"product_id":19,"quantity":2}]',v,'2026-10-09 15:40');
    CALL record_payment(v,'UPI',true,r);
    CALL cancel_order(v);
    CALL place_order(10,'[{"product_id":1,"quantity":1},{"product_id":2,"quantity":1}]',v,'2026-10-10 09:15');
END $$;

-- payments are stamped a few minutes after their order
UPDATE payment p
   SET payment_date = o.order_date + INTERVAL '5 minutes'
  FROM orders o
 WHERE o.order_id = p.order_id;
