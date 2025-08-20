-- =====================================================
-- Claims Invoice Processing System - Database Implementation
-- =====================================================
-- Platform: PostgreSQL
-- Created by: SQL Expert Agent
-- Date: August 10, 2025
-- Version: 1.0
-- Requirements: Based on claims-invoice-requirements.md v1.1
-- =====================================================

-- =====================================================
-- TABLE CREATION
-- =====================================================

-- Groups Table (Client Master Data)
CREATE TABLE Groups (
    GroupID SERIAL PRIMARY KEY,
    Group_Number VARCHAR(20) NOT NULL UNIQUE,
    GroupName VARCHAR(100) NOT NULL,
    FundingMethod VARCHAR(50),
    Type VARCHAR(10) CHECK (Type IN ('RGA', 'HMA')),
    BillingRate DECIMAL(10,4),
    ContactInfo VARCHAR(500),
    Status VARCHAR(20) DEFAULT 'Active',
    CreatedDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Claims Table (Transaction Data with Audit Trail)
CREATE TABLE Claims (
    ClaimID SERIAL PRIMARY KEY,
    Group_Number VARCHAR(20) NOT NULL,
    ClaimNumber VARCHAR(25) NOT NULL,
    ClaimAmount DECIMAL(10,2) NOT NULL CHECK (ClaimAmount > 0),
    Provider VARCHAR(100) NOT NULL,
    MemberName VARCHAR(100) NOT NULL,
    ClaimType VARCHAR(50),
    DateOfService DATE NOT NULL,
    CheckRunDate DATE NOT NULL,
    Check_Number VARCHAR(50) NOT NULL,
    ChargeType VARCHAR(20) NOT NULL CHECK (ChargeType IN ('Paid','RGA','Refund','Void')),
    InvoiceID INTEGER DEFAULT NULL, -- Links to Invoice table for audit trail
    ProcessedDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Foreign key to Groups table
    CONSTRAINT fk_claims_group FOREIGN KEY (Group_Number) REFERENCES Groups(Group_Number)
);

-- Invoice Table (Generated Billing Documents)
CREATE TABLE Invoice (
    InvoiceID SERIAL PRIMARY KEY,
    Group_Number VARCHAR(20) NOT NULL,
    InvoiceDate DATE NOT NULL,
    TotalAmount DECIMAL(10,2) NOT NULL CHECK (TotalAmount > 0),
    Status VARCHAR(20) DEFAULT 'Generated',
    CreatedDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Foreign key to Groups table
    CONSTRAINT fk_invoice_group FOREIGN KEY (Group_Number) REFERENCES Groups(Group_Number)
);

-- FAS Table (Financial Activity Summary)
CREATE TABLE FAS (
    FASID SERIAL PRIMARY KEY,
    Group_Number VARCHAR(20) NOT NULL,
    Amount DECIMAL(10,2) NOT NULL CHECK (Amount > 0),
    Category VARCHAR(50) DEFAULT 'Check Run',
    InvoiceID INTEGER DEFAULT NULL, -- NULL until assigned to invoice
    ProcessDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Foreign keys
    CONSTRAINT fk_fas_group FOREIGN KEY (Group_Number) REFERENCES Groups(Group_Number),
    CONSTRAINT fk_fas_invoice FOREIGN KEY (InvoiceID) REFERENCES Invoice(InvoiceID)
);

-- =====================================================
-- PERFORMANCE INDEXES
-- =====================================================

-- Groups table indexes
CREATE INDEX idx_groups_group_number ON Groups(Group_Number);
CREATE INDEX idx_groups_status ON Groups(Status);

-- DUPLICATE DETECTION INDEX (Critical for 100K claims/week)
-- Composite index on all 6 duplicate detection fields
CREATE INDEX idx_claims_duplicate_detection ON Claims(
    ClaimNumber, Check_Number, CheckRunDate, Provider, MemberName, ClaimAmount
);

-- PROCESSING PERFORMANCE INDEXES
-- Fast lookup for unprocessed claims (NULL invoice processing)
CREATE INDEX idx_claims_unprocessed ON Claims(Group_Number, ChargeType, InvoiceID) 
WHERE InvoiceID IS NULL AND ChargeType = 'Paid';

-- Fast FAS processing
CREATE INDEX idx_fas_unprocessed ON FAS(Group_Number, InvoiceID) 
WHERE InvoiceID IS NULL;

-- AUDIT TRAIL INDEXES
-- Fast "show me all claims for invoice X" queries
CREATE INDEX idx_claims_invoice_id ON Claims(InvoiceID) WHERE InvoiceID IS NOT NULL;
CREATE INDEX idx_fas_invoice_id ON FAS(InvoiceID) WHERE InvoiceID IS NOT NULL;

-- REPORTING INDEXES
-- Fast date-range reporting
CREATE INDEX idx_claims_check_run_date ON Claims(CheckRunDate);
CREATE INDEX idx_invoice_created_date ON Invoice(CreatedDate);

-- Invoice table indexes
CREATE INDEX idx_invoice_group_number ON Invoice(Group_Number);
CREATE INDEX idx_invoice_date ON Invoice(InvoiceDate);

-- =====================================================
-- CORE STORED PROCEDURES
-- =====================================================

-- 1. Duplicate Detection & Claims Import Procedure
CREATE OR REPLACE FUNCTION import_claims_with_duplicate_check(
    p_claim_number VARCHAR(25),
    p_group_number VARCHAR(20),
    p_claim_amount DECIMAL(10,2),
    p_provider VARCHAR(100),
    p_member_name VARCHAR(100),
    p_claim_type VARCHAR(50),
    p_date_of_service DATE,
    p_check_run_date DATE,
    p_check_number VARCHAR(50),
    p_charge_type VARCHAR(20)
) RETURNS TABLE(
    success BOOLEAN,
    message TEXT,
    claim_id INTEGER
) AS $$
DECLARE
    v_claim_id INTEGER;
    v_duplicate_exists BOOLEAN := FALSE;
BEGIN
    -- Check for duplicates using all 6 key fields
    SELECT EXISTS(
        SELECT 1 FROM Claims 
        WHERE ClaimNumber = p_claim_number 
        AND Check_Number = p_check_number
        AND CheckRunDate = p_check_run_date
        AND Provider = p_provider
        AND MemberName = p_member_name  
        AND ClaimAmount = p_claim_amount
    ) INTO v_duplicate_exists;
    
    -- If duplicate found, return without inserting
    IF v_duplicate_exists THEN
        RETURN QUERY SELECT FALSE, 'Duplicate claim detected - skipped'::TEXT, NULL::INTEGER;
        RETURN;
    END IF;
    
    -- Validate Group_Number exists
    IF NOT EXISTS(SELECT 1 FROM Groups WHERE Group_Number = p_group_number) THEN
        RETURN QUERY SELECT FALSE, 'Invalid Group_Number - group does not exist'::TEXT, NULL::INTEGER;
        RETURN;
    END IF;
    
    -- Insert new claim
    INSERT INTO Claims (
        Group_Number, ClaimNumber, ClaimAmount, Provider, MemberName,
        ClaimType, DateOfService, CheckRunDate, Check_Number, ChargeType
    ) VALUES (
        p_group_number, p_claim_number, p_claim_amount, p_provider, p_member_name,
        p_claim_type, p_date_of_service, p_check_run_date, p_check_number, p_charge_type
    ) RETURNING ClaimID INTO v_claim_id;
    
    RETURN QUERY SELECT TRUE, 'Claim imported successfully'::TEXT, v_claim_id;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT FALSE, 'Error importing claim: ' || SQLERRM, NULL::INTEGER;
END;
$$ LANGUAGE plpgsql;

-- 2. Claims Aggregation & FAS Creation Procedure
CREATE OR REPLACE FUNCTION create_fas_entries()
RETURNS TABLE(
    group_number VARCHAR(20),
    total_amount DECIMAL(10,2),
    fas_id INTEGER,
    claims_count INTEGER
) AS $$
DECLARE
    rec RECORD;
    v_fas_id INTEGER;
BEGIN
    -- Aggregate unprocessed 'Paid' claims by Group_Number
    FOR rec IN 
        SELECT 
            c.Group_Number,
            SUM(c.ClaimAmount) as total_amount,
            COUNT(*) as claim_count
        FROM Claims c
        WHERE c.InvoiceID IS NULL 
        AND c.ChargeType = 'Paid'
        GROUP BY c.Group_Number
        HAVING SUM(c.ClaimAmount) > 0
    LOOP
        -- Create FAS entry for this group
        INSERT INTO FAS (Group_Number, Amount, Category)
        VALUES (rec.Group_Number, rec.total_amount, 'Check Run')
        RETURNING FASID INTO v_fas_id;
        
        RETURN QUERY SELECT 
            rec.Group_Number, 
            rec.total_amount, 
            v_fas_id,
            rec.claim_count::INTEGER;
    END LOOP;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- 3. Invoice Generation Procedure
CREATE OR REPLACE FUNCTION generate_invoices()
RETURNS TABLE(
    invoice_id INTEGER,
    group_number VARCHAR(20),
    invoice_date DATE,
    total_amount DECIMAL(10,2),
    fas_entries_count INTEGER
) AS $$
DECLARE
    rec RECORD;
    v_invoice_id INTEGER;
    v_invoice_date DATE;
    v_fas_count INTEGER;
BEGIN
    -- Process each group with unassigned FAS entries
    FOR rec IN 
        SELECT 
            f.Group_Number,
            SUM(f.Amount) as total_amount,
            COUNT(*) as fas_count,
            -- Get invoice date from related claims
            (SELECT c.CheckRunDate 
             FROM Claims c 
             WHERE c.Group_Number = f.Group_Number 
             AND c.InvoiceID IS NULL 
             LIMIT 1) as check_run_date
        FROM FAS f
        WHERE f.InvoiceID IS NULL
        GROUP BY f.Group_Number
        HAVING SUM(f.Amount) > 0
    LOOP
        -- Create invoice for this group
        INSERT INTO Invoice (Group_Number, InvoiceDate, TotalAmount)
        VALUES (rec.Group_Number, rec.check_run_date, rec.total_amount)
        RETURNING InvoiceID INTO v_invoice_id;
        
        RETURN QUERY SELECT 
            v_invoice_id,
            rec.Group_Number,
            rec.check_run_date,
            rec.total_amount,
            rec.fas_count::INTEGER;
    END LOOP;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- 4. Invoice Assignment Procedure (Links Claims & FAS)
CREATE OR REPLACE FUNCTION assign_invoice_numbers()
RETURNS TABLE(
    invoice_id INTEGER,
    group_number VARCHAR(20),
    claims_updated INTEGER,
    fas_updated INTEGER
) AS $$
DECLARE
    rec RECORD;
    v_claims_updated INTEGER;
    v_fas_updated INTEGER;
BEGIN
    -- Process each unassigned invoice
    FOR rec IN 
        SELECT InvoiceID, Group_Number
        FROM Invoice i
        WHERE EXISTS (
            SELECT 1 FROM FAS f 
            WHERE f.Group_Number = i.Group_Number 
            AND f.InvoiceID IS NULL
        )
    LOOP
        -- Update FAS entries for this group/invoice
        UPDATE FAS 
        SET InvoiceID = rec.InvoiceID
        WHERE Group_Number = rec.Group_Number 
        AND InvoiceID IS NULL;
        
        GET DIAGNOSTICS v_fas_updated = ROW_COUNT;
        
        -- Update Claims entries for this group/invoice  
        UPDATE Claims
        SET InvoiceID = rec.InvoiceID
        WHERE Group_Number = rec.Group_Number
        AND InvoiceID IS NULL
        AND ChargeType = 'Paid';
        
        GET DIAGNOSTICS v_claims_updated = ROW_COUNT;
        
        RETURN QUERY SELECT 
            rec.InvoiceID,
            rec.Group_Number,
            v_claims_updated,
            v_fas_updated;
    END LOOP;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- 5. Master Weekly Processing Procedure
CREATE OR REPLACE FUNCTION process_weekly_invoices()
RETURNS TABLE(
    step_name TEXT,
    status TEXT,
    details JSONB
) AS $$
DECLARE
    v_start_time TIMESTAMP;
    v_fas_results RECORD;
    v_invoice_results RECORD;
    v_assign_results RECORD;
    v_total_fas INTEGER := 0;
    v_total_invoices INTEGER := 0;
    v_total_claims_assigned INTEGER := 0;
BEGIN
    v_start_time := CURRENT_TIMESTAMP;
    
    -- Step 1: Create FAS entries from unprocessed claims
    RETURN QUERY SELECT 'FAS_CREATION'::TEXT, 'STARTING'::TEXT, 
        jsonb_build_object('timestamp', v_start_time);
    
    FOR v_fas_results IN SELECT * FROM create_fas_entries() LOOP
        v_total_fas := v_total_fas + 1;
    END LOOP;
    
    RETURN QUERY SELECT 'FAS_CREATION'::TEXT, 'COMPLETED'::TEXT,
        jsonb_build_object('fas_entries_created', v_total_fas);
    
    -- Step 2: Generate invoices from FAS entries
    RETURN QUERY SELECT 'INVOICE_GENERATION'::TEXT, 'STARTING'::TEXT, 
        jsonb_build_object('timestamp', CURRENT_TIMESTAMP);
    
    FOR v_invoice_results IN SELECT * FROM generate_invoices() LOOP
        v_total_invoices := v_total_invoices + 1;
    END LOOP;
    
    RETURN QUERY SELECT 'INVOICE_GENERATION'::TEXT, 'COMPLETED'::TEXT,
        jsonb_build_object('invoices_created', v_total_invoices);
    
    -- Step 3: Assign invoice numbers to claims and FAS
    RETURN QUERY SELECT 'INVOICE_ASSIGNMENT'::TEXT, 'STARTING'::TEXT,
        jsonb_build_object('timestamp', CURRENT_TIMESTAMP);
    
    FOR v_assign_results IN SELECT * FROM assign_invoice_numbers() LOOP
        v_total_claims_assigned := v_total_claims_assigned + v_assign_results.claims_updated;
    END LOOP;
    
    RETURN QUERY SELECT 'INVOICE_ASSIGNMENT'::TEXT, 'COMPLETED'::TEXT,
        jsonb_build_object('claims_assigned', v_total_claims_assigned);
    
    -- Final summary
    RETURN QUERY SELECT 'PROCESS_COMPLETE'::TEXT, 'SUCCESS'::TEXT,
        jsonb_build_object(
            'total_duration_seconds', EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_start_time)),
            'fas_entries_created', v_total_fas,
            'invoices_generated', v_total_invoices,
            'claims_assigned', v_total_claims_assigned
        );
        
EXCEPTION
    WHEN OTHERS THEN
        RETURN QUERY SELECT 'PROCESS_ERROR'::TEXT, 'FAILED'::TEXT,
            jsonb_build_object('error', SQLERRM, 'error_detail', SQLSTATE);
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- REPORTING QUERIES
-- =====================================================

-- 6. Client PDF Summary Report Query
CREATE OR REPLACE FUNCTION get_client_pdf_summary(
    p_group_number VARCHAR(20),
    p_check_run_date DATE
)
RETURNS TABLE(
    group_number VARCHAR(20),
    group_name VARCHAR(100),
    group_type VARCHAR(10),
    funding_method VARCHAR(50),
    check_run_date DATE,
    invoice_count INTEGER,
    total_invoice_amount DECIMAL(10,2),
    total_claims_count INTEGER,
    invoice_numbers TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        g.Group_Number,
        g.GroupName,
        g.Type,
        g.FundingMethod,
        p_check_run_date,
        COUNT(DISTINCT i.InvoiceID)::INTEGER as invoice_count,
        COALESCE(SUM(i.TotalAmount), 0) as total_invoice_amount,
        COUNT(DISTINCT c.ClaimID)::INTEGER as total_claims_count,
        STRING_AGG(DISTINCT i.InvoiceID::TEXT, ', ' ORDER BY i.InvoiceID::TEXT) as invoice_numbers
    FROM Groups g
    LEFT JOIN Invoice i ON g.Group_Number = i.Group_Number 
        AND i.InvoiceDate = p_check_run_date
    LEFT JOIN Claims c ON g.Group_Number = c.Group_Number 
        AND c.CheckRunDate = p_check_run_date
        AND c.InvoiceID IS NOT NULL
    WHERE g.Group_Number = p_group_number
    GROUP BY g.Group_Number, g.GroupName, g.Type, g.FundingMethod;
END;
$$ LANGUAGE plpgsql;

-- 7. Excel FAS Data Sheet Query
CREATE OR REPLACE FUNCTION get_client_fas_data(
    p_group_number VARCHAR(20),
    p_check_run_date DATE
)
RETURNS TABLE(
    fasid INTEGER,
    group_number VARCHAR(20),
    amount DECIMAL(10,2),
    category VARCHAR(50),
    invoice_id INTEGER,
    process_date TIMESTAMP,
    invoice_date DATE,
    invoice_total DECIMAL(10,2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.FASID,
        f.Group_Number,
        f.Amount,
        f.Category,
        f.InvoiceID,
        f.ProcessDate,
        i.InvoiceDate,
        i.TotalAmount as invoice_total
    FROM FAS f
    LEFT JOIN Invoice i ON f.InvoiceID = i.InvoiceID
    WHERE f.Group_Number = p_group_number
    AND EXISTS (
        SELECT 1 FROM Claims c 
        WHERE c.Group_Number = f.Group_Number 
        AND c.CheckRunDate = p_check_run_date
        AND c.InvoiceID = f.InvoiceID
    )
    ORDER BY f.ProcessDate DESC, f.FASID;
END;
$$ LANGUAGE plpgsql;

-- 8. Excel Claims Detail Sheet Query
CREATE OR REPLACE FUNCTION get_client_claims_detail(
    p_group_number VARCHAR(20),
    p_check_run_date DATE
)
RETURNS TABLE(
    claim_id INTEGER,
    group_number VARCHAR(20),
    claim_number VARCHAR(25),
    claim_amount DECIMAL(10,2),
    provider VARCHAR(100),
    member_name VARCHAR(100),
    claim_type VARCHAR(50),
    date_of_service DATE,
    check_run_date DATE,
    check_number VARCHAR(50),
    charge_type VARCHAR(20),
    invoice_id INTEGER,
    processed_date TIMESTAMP,
    days_to_process INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.ClaimID,
        c.Group_Number,
        c.ClaimNumber,
        c.ClaimAmount,
        c.Provider,
        c.MemberName,
        c.ClaimType,
        c.DateOfService,
        c.CheckRunDate,
        c.Check_Number,
        c.ChargeType,
        c.InvoiceID,
        c.ProcessedDate,
        (c.ProcessedDate::DATE - c.DateOfService)::INTEGER as days_to_process
    FROM Claims c
    WHERE c.Group_Number = p_group_number
    AND c.CheckRunDate = p_check_run_date
    AND c.InvoiceID IS NOT NULL  -- Only show invoiced claims
    ORDER BY c.DateOfService DESC, c.ClaimAmount DESC;
END;
$$ LANGUAGE plpgsql;

-- 9. Duplicate Detection Report Query
CREATE OR REPLACE FUNCTION get_duplicate_report(
    p_date_range_start DATE DEFAULT CURRENT_DATE,
    p_date_range_end DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
    duplicate_group INTEGER,
    claim_number VARCHAR(25),
    check_number VARCHAR(50),
    check_run_date DATE,
    provider VARCHAR(100),
    member_name VARCHAR(100),
    claim_amount DECIMAL(10,2),
    group_number VARCHAR(20),
    occurrence_count INTEGER,
    first_processed TIMESTAMP,
    last_attempted TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    WITH duplicate_claims AS (
        SELECT 
            ClaimNumber, Check_Number, CheckRunDate, Provider, MemberName, ClaimAmount,
            COUNT(*) as occurrence_count,
            MIN(ProcessedDate) as first_processed,
            MAX(ProcessedDate) as last_attempted,
            ARRAY_AGG(DISTINCT Group_Number) as group_numbers,
            ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, ClaimNumber) as duplicate_group_id
        FROM Claims
        WHERE ProcessedDate::DATE BETWEEN p_date_range_start AND p_date_range_end
        GROUP BY ClaimNumber, Check_Number, CheckRunDate, Provider, MemberName, ClaimAmount
        HAVING COUNT(*) > 1
    )
    SELECT 
        dc.duplicate_group_id::INTEGER,
        dc.ClaimNumber,
        dc.Check_Number,
        dc.CheckRunDate,
        dc.Provider,
        dc.MemberName,
        dc.ClaimAmount,
        ARRAY_TO_STRING(dc.group_numbers, ', ') as group_number,
        dc.occurrence_count::INTEGER,
        dc.first_processed,
        dc.last_attempted
    FROM duplicate_claims dc
    ORDER BY dc.occurrence_count DESC, dc.ClaimNumber;
END;
$$ LANGUAGE plpgsql;

-- 10. Weekly Processing Summary Report
CREATE OR REPLACE FUNCTION get_weekly_processing_summary(
    p_check_run_date DATE
)
RETURNS TABLE(
    processing_date DATE,
    total_groups_processed INTEGER,
    total_claims_imported INTEGER,
    total_claim_amount DECIMAL(10,2),
    total_invoices_generated INTEGER,
    total_invoice_amount DECIMAL(10,2),
    duplicates_detected INTEGER,
    errors_encountered INTEGER,
    processing_status TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p_check_run_date,
        COUNT(DISTINCT c.Group_Number)::INTEGER as groups_processed,
        COUNT(c.ClaimID)::INTEGER as claims_imported,
        COALESCE(SUM(c.ClaimAmount), 0) as total_claim_amount,
        COUNT(DISTINCT i.InvoiceID)::INTEGER as invoices_generated,
        COALESCE(SUM(DISTINCT i.TotalAmount), 0) as total_invoice_amount,
        -- Duplicate count (simplified - would need log table for accurate count)
        0::INTEGER as duplicates_detected,
        -- Error count (simplified - would need error log table)
        0::INTEGER as errors_encountered,
        CASE 
            WHEN COUNT(DISTINCT i.InvoiceID) > 0 THEN 'COMPLETED'
            WHEN COUNT(c.ClaimID) > 0 THEN 'PARTIAL'
            ELSE 'NO_DATA'
        END as processing_status
    FROM Claims c
    LEFT JOIN Invoice i ON c.InvoiceID = i.InvoiceID
    WHERE c.CheckRunDate = p_check_run_date;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- SAMPLE DATA INSERTION (FOR TESTING)
-- =====================================================

-- Insert sample groups
INSERT INTO Groups (Group_Number, GroupName, FundingMethod, Type) VALUES
('GRP001', 'Acme Corporation', 'Self-Funded', 'RGA'),
('GRP002', 'Beta Industries', 'Insured', 'HMA'),
('GRP003', 'Gamma Solutions', 'Hybrid', 'RGA');

-- =====================================================
-- USAGE EXAMPLES
-- =====================================================

-- Example 1: Import a claim with duplicate check
-- SELECT * FROM import_claims_with_duplicate_check(
--     '1234567890', 'GRP001', 150.00, 'Provider ABC', 'John Doe', 
--     'Medical', '2025-08-01', '2025-08-10', 'CHK001', 'Paid'
-- );

-- Example 2: Run full weekly processing
-- SELECT * FROM process_weekly_invoices();

-- Example 3: Generate client PDF summary
-- SELECT * FROM get_client_pdf_summary('GRP001', '2025-08-10');

-- Example 4: Get duplicate report
-- SELECT * FROM get_duplicate_report('2025-08-01', '2025-08-31');

-- =====================================================
-- END OF DATABASE IMPLEMENTATION
-- =====================================================