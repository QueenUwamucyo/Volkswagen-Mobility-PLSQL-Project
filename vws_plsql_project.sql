
-- Volkswagen Mobility Solutions Data Management System
-- Full runnable script for SQL*Plus
-- Save as vws_plsql_project.sql and run in SQL*Plus: SQL> @vws_plsql_project.sql
-- Requirements: Oracle user with CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER, CREATE PACKAGE privileges.

SET ECHO ON
SET SERVEROUTPUT ON SIZE 1000000
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT -----------------------------
PROMPT VWS PL/SQL Project - Start
PROMPT -----------------------------

-- 0. Safe drop of objects (ignore errors)
BEGIN
  FOR c IN (SELECT object_name, object_type FROM user_objects 
            WHERE object_name IN (
              'VWS_MGMT','VEHICLE','CUSTOMER','LOCATION','TARIFF','BOOKING',
              'MAINTENANCE','USAGE_LOG','AUDIT_LOG',
              'SEQ_VEHICLE_ID','SEQ_CUSTOMER_ID','SEQ_BOOKING_ID','SEQ_MAINTENANCE_ID'
            )) LOOP
    BEGIN
      IF c.object_type = 'PACKAGE' OR c.object_type = 'PACKAGE BODY' THEN
        EXECUTE IMMEDIATE 'DROP ' || c.object_type || ' ' || c.object_name;
      ELSE
        BEGIN
          EXECUTE IMMEDIATE 'DROP ' || c.object_type || ' ' || c.object_name || ' CASCADE CONSTRAINTS';
        EXCEPTION WHEN OTHERS THEN
          -- ignore
          NULL;
        END;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
/
-- Also try dropping sequences individually (ignore errors)
BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_vehicle_id';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_customer_id';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_booking_id';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_maintenance_id';
EXCEPTION WHEN OTHERS THEN NULL; END;
/

PROMPT Creating sequences...
-- 1. Sequences
CREATE SEQUENCE seq_vehicle_id START WITH 1000 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_customer_id START WITH 5000 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_booking_id START WITH 100000 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_maintenance_id START WITH 7000 INCREMENT BY 1 NOCACHE NOCYCLE;
/

PROMPT Creating tables...
-- 2. Core tables
CREATE TABLE vehicle (
  vehicle_id       NUMBER PRIMARY KEY,
  vin              VARCHAR2(32) UNIQUE NOT NULL,
  model            VARCHAR2(100) NOT NULL,
  year             NUMBER(4),
  current_location NUMBER,
  status           VARCHAR2(20) DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE','IN_USE','MAINTENANCE','RESERVED')),
  battery_level    NUMBER(3) CHECK (battery_level BETWEEN 0 AND 100),
  mileage_km       NUMBER DEFAULT 0,
  last_maintenance_date DATE,
  created_at       TIMESTAMP DEFAULT SYSTIMESTAMP
);
/
CREATE TABLE customer (
  customer_id      NUMBER PRIMARY KEY,
  full_name        VARCHAR2(200) NOT NULL,
  email            VARCHAR2(150) UNIQUE NOT NULL,
  phone            VARCHAR2(30),
  driver_license   VARCHAR2(50),
  registered_at    TIMESTAMP DEFAULT SYSTIMESTAMP
);
/
CREATE TABLE location (
  location_id      NUMBER PRIMARY KEY,
  name             VARCHAR2(150) NOT NULL,
  address          VARCHAR2(400),
  latitude         VARCHAR2(32),
  longitude        VARCHAR2(32)
);
/
CREATE TABLE tariff (
  tariff_id        NUMBER PRIMARY KEY,
  name             VARCHAR2(100),
  per_minute       NUMBER(10,2) DEFAULT 0,
  per_km           NUMBER(10,2) DEFAULT 0,
  base_fare        NUMBER(10,2) DEFAULT 0,
  active           CHAR(1) DEFAULT 'Y' CHECK (active IN ('Y','N'))
);
/
CREATE TABLE booking (
  booking_id       NUMBER PRIMARY KEY,
  vehicle_id       NUMBER NOT NULL,
  customer_id      NUMBER NOT NULL,
  start_time       TIMESTAMP NOT NULL,
  end_time         TIMESTAMP,
  start_location   NUMBER,
  end_location     NUMBER,
  start_mileage_km NUMBER,
  end_mileage_km   NUMBER,
  estimated_cost   NUMBER(12,2),
  actual_cost      NUMBER(12,2),
  status           VARCHAR2(20) DEFAULT 'BOOKED' CHECK (status IN ('BOOKED','ONGOING','COMPLETED','CANCELLED')),
  tariff_id        NUMBER,
  created_at       TIMESTAMP DEFAULT SYSTIMESTAMP,
  CONSTRAINT fk_booking_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicle(vehicle_id),
  CONSTRAINT fk_booking_customer FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
  CONSTRAINT fk_booking_startloc FOREIGN KEY (start_location) REFERENCES location(location_id),
  CONSTRAINT fk_booking_endloc FOREIGN KEY (end_location) REFERENCES location(location_id),
  CONSTRAINT fk_booking_tariff FOREIGN KEY (tariff_id) REFERENCES tariff(tariff_id)
);
/
CREATE TABLE maintenance (
  maintenance_id   NUMBER PRIMARY KEY,
  vehicle_id       NUMBER NOT NULL,
  scheduled_date   DATE NOT NULL,
  completed_date   DATE,
  type             VARCHAR2(100),
  notes            CLOB,
  status           VARCHAR2(20) DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED','IN_PROGRESS','COMPLETED','CANCELLED')),
  CONSTRAINT fk_maint_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicle(vehicle_id)
);
/
CREATE TABLE usage_log (
  usage_id         NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY PRIMARY KEY,
  booking_id       NUMBER,
  timestamp        TIMESTAMP DEFAULT SYSTIMESTAMP,
  event_type       VARCHAR2(60),
  details          CLOB
);
/
CREATE TABLE audit_log (
  audit_id         NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY PRIMARY KEY,
  object_type      VARCHAR2(50),
  object_id        VARCHAR2(100),
  action           VARCHAR2(50),
  performed_by     VARCHAR2(100),
  performed_at     TIMESTAMP DEFAULT SYSTIMESTAMP,
  details          CLOB
);
/

PROMPT Creating triggers...
-- Triggers
CREATE OR REPLACE TRIGGER trg_vehicle_pk
BEFORE INSERT ON vehicle
FOR EACH ROW
BEGIN
  IF :NEW.vehicle_id IS NULL THEN
    :NEW.vehicle_id := seq_vehicle_id.NEXTVAL;
  END IF;
END;
/
CREATE OR REPLACE TRIGGER trg_customer_pk
BEFORE INSERT ON customer
FOR EACH ROW
BEGIN
  IF :NEW.customer_id IS NULL THEN
    :NEW.customer_id := seq_customer_id.NEXTVAL;
  END IF;
END;
/
CREATE OR REPLACE TRIGGER trg_booking_pk
BEFORE INSERT ON booking
FOR EACH ROW
BEGIN
  IF :NEW.booking_id IS NULL THEN
    :NEW.booking_id := seq_booking_id.NEXTVAL;
  END IF;
END;
/
CREATE OR REPLACE TRIGGER trg_maintenance_pk
BEFORE INSERT ON maintenance
FOR EACH ROW
BEGIN
  IF :NEW.maintenance_id IS NULL THEN
    :NEW.maintenance_id := seq_maintenance_id.NEXTVAL;
  END IF;
END;
/
CREATE OR REPLACE TRIGGER trg_audit_vehicle_status
AFTER UPDATE OF status ON vehicle
FOR EACH ROW
BEGIN
  INSERT INTO audit_log(object_type, object_id, action, performed_by, details)
  VALUES ('VEHICLE', NVL(TO_CHAR(:NEW.vehicle_id), 'UNKNOWN'), 'STATUS_CHANGE', SYS_CONTEXT('USERENV','SESSION_USER'),
          'Status changed from ' || :OLD.status || ' to ' || :NEW.status);
END;
/

PROMPT Creating package specification...
-- Package spec
CREATE OR REPLACE PACKAGE vws_mgmt AS
  TYPE t_vehicle_rec IS RECORD (
    vehicle_id NUMBER,
    vin VARCHAR2(32)
  );
  e_not_available EXCEPTION;
  e_invalid_booking EXCEPTION;
  PROCEDURE add_vehicle(p_vin IN VARCHAR2, p_model IN VARCHAR2, p_year IN NUMBER, p_location IN NUMBER, p_mileage IN NUMBER, p_battery IN NUMBER);
  PROCEDURE register_customer(p_name IN VARCHAR2, p_email IN VARCHAR2, p_phone IN VARCHAR2, p_license IN VARCHAR2, p_out_customer_id OUT NUMBER);
  PROCEDURE create_booking(p_vehicle_id IN NUMBER, p_customer_id IN NUMBER, p_start_time IN TIMESTAMP, p_start_loc IN NUMBER, p_tariff_id IN NUMBER, p_out_booking_id OUT NUMBER);
  PROCEDURE start_booking(p_booking_id IN NUMBER, p_now IN TIMESTAMP);
  PROCEDURE end_booking(p_booking_id IN NUMBER, p_end_time IN TIMESTAMP, p_end_loc IN NUMBER, p_end_mileage IN NUMBER, p_out_cost OUT NUMBER);
  PROCEDURE schedule_maintenance(p_vehicle_id IN NUMBER, p_date IN DATE, p_type IN VARCHAR2, p_notes IN CLOB, p_out_maint_id OUT NUMBER);
  PROCEDURE complete_maintenance(p_maint_id IN NUMBER, p_completed_date IN DATE);
  FUNCTION get_vehicle_status(p_vehicle_id IN NUMBER) RETURN VARCHAR2;
  FUNCTION monthly_usage_report(p_month IN NUMBER, p_year IN NUMBER) RETURN SYS_REFCURSOR;
END vws_mgmt;
/
PROMPT Creating package body...
-- Package body
CREATE OR REPLACE PACKAGE BODY vws_mgmt AS
  FUNCTION calc_distance_km(p_from_loc IN NUMBER, p_to_loc IN NUMBER) RETURN NUMBER IS
  BEGIN
    IF p_from_loc = p_to_loc THEN
      RETURN 1;
    ELSE
      RETURN 5 + ABS(NVL(p_from_loc,0) - NVL(p_to_loc,0)) * 0.1;
    END IF;
  END;
  PROCEDURE add_vehicle(p_vin IN VARCHAR2, p_model IN VARCHAR2, p_year IN NUMBER, p_location IN NUMBER, p_mileage IN NUMBER, p_battery IN NUMBER) IS
    v_id NUMBER;
  BEGIN
    INSERT INTO vehicle(vehicle_id, vin, model, year, current_location, mileage_km, battery_level, status)
    VALUES (seq_vehicle_id.NEXTVAL, p_vin, p_model, p_year, p_location, NVL(p_mileage,0), NVL(p_battery,100), 'AVAILABLE')
    RETURNING vehicle_id INTO v_id;
    INSERT INTO audit_log(object_type, object_id, action, performed_by, details)
    VALUES ('VEHICLE', TO_CHAR(v_id), 'CREATE', SYS_CONTEXT('USERENV','SESSION_USER'), 'Added vehicle: '||p_model||' VIN: '||p_vin);
    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
  END add_vehicle;
  PROCEDURE register_customer(p_name IN VARCHAR2, p_email IN VARCHAR2, p_phone IN VARCHAR2, p_license IN VARCHAR2, p_out_customer_id OUT NUMBER) IS
  BEGIN
    INSERT INTO customer(customer_id, full_name, email, phone, driver_license)
    VALUES (seq_customer_id.NEXTVAL, p_name, p_email, p_phone, p_license)
    RETURNING customer_id INTO p_out_customer_id;
    INSERT INTO audit_log(object_type, object_id, action, performed_by, details)
    VALUES ('CUSTOMER', TO_CHAR(p_out_customer_id), 'REGISTER', SYS_CONTEXT('USERENV','SESSION_USER'), 'Registered: '||p_name);
    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
  END register_customer;
  PROCEDURE create_booking(p_vehicle_id IN NUMBER, p_customer_id IN NUMBER, p_start_time IN TIMESTAMP, p_start_loc IN NUMBER, p_tariff_id IN NUMBER, p_out_booking_id OUT NUMBER) IS
    v_status VARCHAR2(20);
    v_start_mileage NUMBER;
    v_tariff_per_min NUMBER(10,2);
  BEGIN
    SELECT status, mileage_km INTO v_status, v_start_mileage FROM vehicle WHERE vehicle_id = p_vehicle_id FOR UPDATE;
    IF v_status <> 'AVAILABLE' THEN
      RAISE e_not_available;
    END IF;
    SELECT per_minute INTO v_tariff_per_min FROM tariff WHERE tariff_id = p_tariff_id;
    INSERT INTO booking(booking_id, vehicle_id, customer_id, start_time, start_location, start_mileage_km, tariff_id, status)
    VALUES (seq_booking_id.NEXTVAL, p_vehicle_id, p_customer_id, p_start_time, p_start_loc, v_start_mileage, p_tariff_id, 'BOOKED')
    RETURNING booking_id INTO p_out_booking_id;
    UPDATE vehicle SET status = 'RESERVED' WHERE vehicle_id = p_vehicle_id;
    INSERT INTO usage_log(booking_id, event_type, details) VALUES (p_out_booking_id, 'CREATE_BOOKING', 'Booked at '||TO_CHAR(p_start_time));
    INSERT INTO audit_log(object_type, object_id, action, performed_by, details)
    VALUES ('BOOKING', TO_CHAR(p_out_booking_id), 'CREATE', SYS_CONTEXT('USERENV','SESSION_USER'), 'Booking created for vehicle '||p_vehicle_id);
    COMMIT;
  EXCEPTION WHEN e_not_available THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20001, 'Vehicle not available for booking.');
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20002, 'Tariff or vehicle not found.');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
  END create_booking;
  PROCEDURE start_booking(p_booking_id IN NUMBER, p_now IN TIMESTAMP) IS
    v_vehicle_id NUMBER;
    v_status VARCHAR2(20);
  BEGIN
    SELECT vehicle_id INTO v_vehicle_id FROM booking WHERE booking_id = p_booking_id FOR UPDATE;
    SELECT status INTO v_status FROM vehicle WHERE vehicle_id = v_vehicle_id FOR UPDATE;
    IF v_status NOT IN ('AVAILABLE','RESERVED') THEN
      RAISE_APPLICATION_ERROR(-20003, 'Vehicle cannot be started (not available).');
    END IF;
    UPDATE booking SET status = 'ONGOING', start_time = p_now WHERE booking_id = p_booking_id;
    UPDATE vehicle SET status = 'IN_USE' WHERE vehicle_id = v_vehicle_id;
    INSERT INTO usage_log(booking_id, event_type, details) VALUES (p_booking_id, 'START', 'Started at '||TO_CHAR(p_now));
    COMMIT;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20004, 'Booking not found.');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
  END start_booking;
  PROCEDURE end_booking(p_booking_id IN NUMBER, p_end_time IN TIMESTAMP, p_end_loc IN NUMBER, p_end_mileage IN NUMBER, p_out_cost OUT NUMBER) IS
    v_vehicle_id NUMBER;
    v_tariff_id NUMBER;
    v_start_time TIMESTAMP;
    v_start_mileage NUMBER;
    v_per_min NUMBER;
    v_per_km NUMBER;
    v_base NUMBER;
    v_minutes NUMBER;
    v_distance NUMBER;
    v_cost NUMBER(12,2);
  BEGIN
    SELECT vehicle_id, start_time, start_mileage_km, tariff_id INTO v_vehicle_id, v_start_time, v_start_mileage, v_tariff_id FROM booking WHERE booking_id = p_booking_id FOR UPDATE;
    SELECT per_minute, per_km, base_fare INTO v_per_min, v_per_km, v_base FROM tariff WHERE tariff_id = v_tariff_id;
    v_minutes := CEIL((CAST(p_end_time AS DATE) - CAST(v_start_time AS DATE)) * 24 * 60);
    IF v_minutes < 0 THEN v_minutes := 0; END IF;
    IF p_end_mileage IS NOT NULL AND v_start_mileage IS NOT NULL THEN
      v_distance := NVL(p_end_mileage, v_start_mileage) - NVL(v_start_mileage, 0);
      IF v_distance < 0 THEN v_distance := 0; END IF;
    ELSE
      v_distance := calc_distance_km(NULL, NULL);
    END IF;
    v_cost := NVL(v_base,0) + (NVL(v_per_min,0) * v_minutes) + (NVL(v_per_km,0) * v_distance);
    UPDATE booking
    SET end_time = p_end_time,
        end_location = p_end_loc,
        end_mileage_km = p_end_mileage,
        actual_cost = v_cost,
        status = 'COMPLETED'
    WHERE booking_id = p_booking_id;
    UPDATE vehicle
    SET mileage_km = NVL(p_end_mileage, mileage_km),
        current_location = p_end_loc,
        status = 'AVAILABLE'
    WHERE vehicle_id = v_vehicle_id;
    INSERT INTO usage_log(booking_id, event_type, details)
    VALUES (p_booking_id, 'END', 'Ended at '||TO_CHAR(p_end_time)||' cost='||TO_CHAR(v_cost));
    INSERT INTO audit_log(object_type, object_id, action, performed_by, details)
    VALUES ('BOOKING', TO_CHAR(p_booking_id), 'COMPLETE', SYS_CONTEXT('USERENV','SESSION_USER'), 'Completed cost='||TO_CHAR(v_cost));
    p_out_cost := v_cost;
    COMMIT;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    RAISE_APPLICATION_ERROR(-20005, 'Booking or tariff not found.');
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
  END end_booking;
  PROCEDURE schedule_maintenance(p_vehicle_id IN NUMBER, p_date IN DATE, p_type IN VARCHAR2, p_notes IN CLOB, p_out_maint_id OUT NUMBER) IS
  BEGIN
    INSERT INTO maintenance(maintenance_id, vehicle_id, scheduled_date, type, notes, status)
    VALUES (seq_maintenance_id.NEXTVAL, p_vehicle_id, p_date, p_type, p_notes, 'SCHEDULED')
    RETURNING maintenance_id INTO p_out_maint_id;
    UPDATE vehicle SET status = 'MAINTENANCE' WHERE vehicle_id = p_vehicle_id;
    INSERT INTO audit_log(object_type, object_id, action, performed_by, details)
    VALUES ('MAINTENANCE', TO_CHAR(p_out_maint_id), 'SCHEDULE', SYS_CONTEXT('USERENV','SESSION_USER'), 'Scheduled '||p_type);
    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
  END schedule_maintenance;
  PROCEDURE complete_maintenance(p_maint_id IN NUMBER, p_completed_date IN DATE) IS
    v_vehicle_id NUMBER;
  BEGIN
    SELECT vehicle_id INTO v_vehicle_id FROM maintenance WHERE maintenance_id = p_maint_id FOR UPDATE;
    UPDATE maintenance SET status = 'COMPLETED', completed_date = p_completed_date WHERE maintenance_id = p_maint_id;
    UPDATE vehicle SET last_maintenance_date = p_completed_date, status = 'AVAILABLE' WHERE vehicle_id = v_vehicle_id;
    INSERT INTO audit_log(object_type, object_id, action, performed_by, details)
    VALUES ('MAINTENANCE', TO_CHAR(p_maint_id), 'COMPLETE', SYS_CONTEXT('USERENV','SESSION_USER'), 'Completed on '||TO_CHAR(p_completed_date));
    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
  END complete_maintenance;
  FUNCTION get_vehicle_status(p_vehicle_id IN NUMBER) RETURN VARCHAR2 IS
    v_status VARCHAR2(20);
  BEGIN
    SELECT status INTO v_status FROM vehicle WHERE vehicle_id = p_vehicle_id;
    RETURN v_status;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RETURN 'UNKNOWN';
  END get_vehicle_status;
  FUNCTION monthly_usage_report(p_month IN NUMBER, p_year IN NUMBER) RETURN SYS_REFCURSOR IS
    rc SYS_REFCURSOR;
  BEGIN
    OPEN rc FOR
      SELECT b.booking_id, b.vehicle_id, v.model, b.customer_id, c.full_name, b.start_time, b.end_time, b.actual_cost
      FROM booking b
      JOIN vehicle v ON b.vehicle_id = v.vehicle_id
      LEFT JOIN customer c ON b.customer_id = c.customer_id
      WHERE EXTRACT(MONTH FROM NVL(b.start_time, SYSTIMESTAMP)) = p_month
        AND EXTRACT(YEAR FROM NVL(b.start_time, SYSTIMESTAMP)) = p_year
      ORDER BY b.start_time DESC;
    RETURN rc;
  END monthly_usage_report;
END vws_mgmt;
/
PROMPT Package created.

PROMPT Seeding sample data...
-- Seed data (locations & tariffs)
INSERT INTO location(location_id, name, address, latitude, longitude) VALUES(1,'Kigali Downtown','Downtown, Kigali','-1.9441','30.0619');
INSERT INTO location(location_id, name, address) VALUES(2,'ACU Campus','AUCA campus','-1.9470','30.0910');
INSERT INTO location(location_id, name, address) VALUES(3,'Airport','Kigali Intl Airport','-1.9686','30.1390');
INSERT INTO tariff(tariff_id, name, per_minute, per_km, base_fare, active) VALUES(1,'Standard', 0.15, 0.3, 0.5, 'Y');
INSERT INTO tariff(tariff_id, name, per_minute, per_km, base_fare, active) VALUES(2,'Premium', 0.25, 0.5, 1.0, 'Y');
COMMIT;
PROMPT Sample data inserted.

PROMPT Example package calls (tests)...
-- Example usage: add vehicles and a customer (uncomment if you want to run)
BEGIN
  vws_mgmt.add_vehicle('WVWZZZ1JZXW000001','Volkswagen e-Golf',2020,1,12000,88);
  vws_mgmt.add_vehicle('WVWZZZ1JZXW000002','Volkswagen ID.3',2021,2,8000,94);
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Warning: add_vehicle failed - '||SQLERRM);
END;
/
-- register a sample customer
DECLARE
  c_id NUMBER;
BEGIN
  vws_mgmt.register_customer('Jean Uwimana','jean.u@example.com','+250788000000','RWA-DR-1234', c_id);
  DBMS_OUTPUT.PUT_LINE('Customer created: '||c_id);
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Warning: register_customer failed - '||SQLERRM);
END;
/

PROMPT Running a sample booking flow...
DECLARE
  b_id NUMBER;
  c_id NUMBER;
  cost NUMBER;
BEGIN
  SELECT customer_id INTO c_id FROM customer WHERE email='jean.u@example.com';
  vws_mgmt.create_booking(
    p_vehicle_id => (SELECT vehicle_id FROM vehicle WHERE vin='WVWZZZ1JZXW000001'),
    p_customer_id => c_id,
    p_start_time => SYSTIMESTAMP + INTERVAL '1' MINUTE,
    p_start_loc => 1,
    p_tariff_id => 1,
    p_out_booking_id => b_id
  );
  DBMS_OUTPUT.PUT_LINE('Booking created: '||b_id);

  vws_mgmt.start_booking(b_id, SYSTIMESTAMP);
  DBMS_OUTPUT.PUT_LINE('Started booking '||b_id);

  vws_mgmt.end_booking(b_id, SYSTIMESTAMP + INTERVAL '15' MINUTE, 2, (SELECT mileage_km FROM vehicle WHERE vehicle_id=(SELECT vehicle_id FROM booking WHERE booking_id = b_id))+12, cost);
  DBMS_OUTPUT.PUT_LINE('Booking ended. Cost: '||TO_CHAR(cost));
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Sample flow error: ' || SQLERRM);
END;
/

PROMPT -----------------------------
PROMPT VWS PL/SQL Project - Done
PROMPT -----------------------------
EXIT
