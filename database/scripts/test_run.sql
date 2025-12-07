SELECT mobility_pkg.calculate_fare(30) FROM dual;

SELECT mobility_pkg.customer_discount(1) FROM dual;

EXEC mobility_pkg.add_trip(1, 1, 1, 20);

SELECT * FROM Trips ORDER BY trip_id DESC;

EXEC mobility_pkg.record_payment(1, 'MTN');

EXEC mobility_pkg.record_maintenance(1, 50000, 'Oil change');
