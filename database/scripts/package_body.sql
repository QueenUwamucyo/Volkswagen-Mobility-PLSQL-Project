CREATE OR REPLACE PACKAGE BODY mobility_pkg AS

  FUNCTION calculate_fare(p_distance NUMBER)
  RETURN NUMBER AS
  BEGIN
    RETURN p_distance * 680;
  END;

  FUNCTION check_vehicle_available(p_vehicle_id NUMBER)
  RETURN NUMBER AS
    v_status VARCHAR2(20);
  BEGIN
    SELECT status INTO v_status FROM Vehicles WHERE vehicle_id = p_vehicle_id;

    IF v_status = 'Available' THEN RETURN 1;
    ELSE RETURN 0;
    END IF;
  END;

  FUNCTION customer_discount(p_customer_id NUMBER)
  RETURN NUMBER AS
    v_type VARCHAR2(20);
  BEGIN
    SELECT membership_type INTO v_type FROM Customers WHERE customer_id = p_customer_id;

    IF v_type='Premium' THEN RETURN 15;
    ELSIF v_type='Gold' THEN RETURN 10;
    ELSE RETURN 0;
    END IF;
  END;

  PROCEDURE add_trip(
    p_vehicle_id NUMBER,
    p_driver_id NUMBER,
    p_customer_id NUMBER,
    p_distance_km NUMBER
  ) AS
    v_available NUMBER;
    v_trip NUMBER;
  BEGIN
    v_available := check_vehicle_available(p_vehicle_id);
    IF v_available = 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'Vehicle not available');
    END IF;

    v_trip := trips_seq.NEXTVAL;

    INSERT INTO Trips(trip_id, vehicle_id, driver_id, customer_id, start_time, distance_km)
    VALUES (v_trip, p_vehicle_id, p_driver_id, p_customer_id, SYSDATE, p_distance_km);

    UPDATE Vehicles
    SET status='On Trip'
    WHERE vehicle_id = p_vehicle_id;

    COMMIT;
  END;

  PROCEDURE record_payment(p_trip_id NUMBER, p_method VARCHAR2) AS
    v_amount NUMBER;
  BEGIN
    SELECT fare INTO v_amount FROM Trips WHERE trip_id = p_trip_id;

    INSERT INTO Payments(payment_id, trip_id, amount, payment_method, timestamp)
    VALUES (payments_seq.NEXTVAL, p_trip_id, v_amount, p_method, SYSDATE);

    COMMIT;
  END;

  PROCEDURE record_maintenance(p_vehicle_id NUMBER, p_cost NUMBER, p_details VARCHAR2) AS
  BEGIN
    INSERT INTO Maintenance(maint_id, vehicle_id, service_date, cost, details)
    VALUES (maint_seq.NEXTVAL, p_vehicle_id, SYSDATE, p_cost, p_details);

    UPDATE Vehicles
    SET status='Maintenance'
    WHERE vehicle_id = p_vehicle_id;

    COMMIT;
  END;

END mobility_pkg;
/
