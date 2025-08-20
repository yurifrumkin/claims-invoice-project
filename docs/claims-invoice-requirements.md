# Claims Invoice Processing System - Technical Requirements

## Document Information
- **Created**: August 10, 2025
- **Version**: 1.2
- **Requirements Analyst**: Enhanced Requirements Analyst Agent
- **Business Sponsor**: Finance Operations Team
- **Status**: Updated with comprehensive UI/UX requirements
- **Last Updated**: August 12, 2025

## Version History
- **v1.0**: Initial requirements from business analysis
- **v1.1**: Added database platform choice, invoice assignment rules, and process optimizations (SQL Expert feedback)
- **v1.2**: Added comprehensive User Interface and User Experience requirements with 5 primary interfaces, performance standards, accessibility compliance, and mobile access specifications

## Business Process Overview

### Primary Business Outcome
Generate weekly invoices for 300 clients based on processed claims data, enabling cash flow management for third-party claims administration.

### Key Business Rules
- Must invoice and collect funds before paying vendors on clients' behalf
- Weekly processing cycle (traditional client expectation)
- Volume: 100,000 claims per week across 300 clients
- All current process claims have Charge Type = "Paid"

## Data Requirements

### Source Data Format (CSV Import)
**File Structure**: Weekly CSV files containing claims data
**Fields Required**:
- Claim Number: nvarchar(25) - Variable length 10-25 digits
- Claim Amount: currency
- Provider: text field
- Member Name: text field  
- Claim Type: predefined values
- Date of Service: date format
- Check Run Date: date (used for Invoice Date)
- Check_Number: text
- Charge Type: "Paid", "RGA", "Refund", "Void" (current process uses only "Paid")

### Database Schema Requirements

#### Groups Table (Client Master Data)
```
GroupID: int (identity/auto-increment primary key)
Group_Number: nvarchar(20) (unique business key)
GroupName: nvarchar(100) (required)
FundingMethod: nvarchar(50) (business categorization)
Type: nvarchar(10) (CHECK constraint: "RGA" or "HMA")
BillingRate: decimal(10,4) (optional)
ContactInfo: nvarchar(500) (optional)
Status: nvarchar(20) (default "Active")
CreatedDate: datetime (default current timestamp)
```

#### Claims Table (Imported Transaction Data)
```
ClaimID: int (identity/auto-increment primary key) 
Group_Number: nvarchar(20) (foreign key to Groups)
ClaimNumber: nvarchar(25) (part of duplicate detection key)
ClaimAmount: decimal(10,2) (currency)
Provider: nvarchar(100)
MemberName: nvarchar(100)
ClaimType: nvarchar(50)
DateOfService: date
CheckRunDate: date (becomes Invoice Date)
Check_Number: nvarchar(50) (part of duplicate detection key)
ChargeType: nvarchar(20) (CHECK constraint: "Paid","RGA","Refund","Void")
InvoiceID: int (foreign key to Invoice, initially NULL, updated after invoice creation)
ProcessedDate: datetime (default current timestamp)
```

#### FAS Table (Financial Activity Summary)
```
FASID: int (identity/auto-increment primary key)
Group_Number: nvarchar(20) (foreign key to Groups)
Amount: decimal(10,2) (aggregated from Claims)
Category: nvarchar(50) (value = "Check Run")
InvoiceNumber: int (foreign key to Invoice, initially NULL)
ProcessDate: datetime (default current timestamp)
```

#### Invoice Table (Generated Invoices)
```
InvoiceID: int (identity/auto-increment primary key)
Group_Number: nvarchar(20) (foreign key to Groups)
InvoiceDate: date (from Claims.CheckRunDate)
TotalAmount: decimal(10,2) (sum of assigned FAS entries)
Status: nvarchar(20) (default "Generated")
CreatedDate: datetime (default current timestamp)
```

## Business Process Workflow

### Step 1: CSV Import with Duplicate Detection
**Input**: Weekly CSV file with claims data
**Process**: 
- Validate file format and required fields
- Check for duplicates against entire Claims database
- Duplicate criteria (all must match): ClaimNumber + Check_Number + CheckRunDate + Provider + MemberName + Amount
**Output**: 
- Successfully imported claims in Claims table
- Duplicate report for any skipped records
- Email notification to yuri.d.frumkin@gmail.com if duplicates found
**Error Handling**: Continue processing file, skip duplicates, log all issues

### Step 2: Claims Aggregation
**Input**: Newly imported Claims records (ChargeType = "Paid" AND InvoiceID IS NULL)
**Process**: Group by Group_Number, sum ClaimAmount
**Output**: Aggregated totals by Group_Number for FAS creation
**Business Rules**: 
- Only process claims with ChargeType = "Paid"
- Only process claims not previously invoiced (InvoiceID IS NULL)
- This prevents double-billing and supports incremental processing

### Step 3: FAS Entry Creation  
**Input**: Aggregated claims data by Group_Number
**Process**: Insert one record per Group_Number in FAS table
**Fields**: Group_Number, Amount (sum), Category = "Check Run", InvoiceNumber = NULL
**Output**: FAS records ready for invoice assignment

### Step 4: Invoice Generation
**Input**: FAS records with NULL InvoiceNumber for each Group_Number  
**Process**: Create invoice record per Group_Number
**Fields**: Group_Number, InvoiceDate (from Claims.CheckRunDate), TotalAmount (sum of FAS amounts)
**Business Rule**: Only process FAS entries where InvoiceID IS NULL (prevents double-billing)
**Output**: Invoice records with generated InvoiceID

### Step 5: Invoice Assignment
**Input**: New Invoice records and unassigned Claims/FAS records
**Process**: Update both Claims AND FAS records to link InvoiceID = generated InvoiceID
**Business Rules**: 
- All unassigned FAS entries for a Group_Number get assigned to the new invoice
- All related Claims for the same Group_Number get assigned the same InvoiceID
- This enables audit trail: "Show me all claims for Invoice #12345"
**Output**: Fully linked Invoice, FAS, and Claims records with complete traceability

### Step 6: Client Reporting
**For each of the 300 clients:**

#### PDF Summary Report
- **Content**: Group information + Current Check Run Date
- **Format**: Professional layout with company logo and branding
- **Naming**: `GroupNumber_CheckRunDate_Summary.pdf`
- **Storage**: Weekly folders organized by processing date

#### Excel Detail Report
- **Sheet 1**: "FAS Data" - All FAS table columns for this Group_Number
- **Sheet 2**: "Claims Detail" - All Claims table columns for this Group_Number  
- **Format**: Professional formatting with company logo
- **Naming**: `GroupNumber_CheckRunDate_Detail.xlsx`
- **Storage**: Same weekly folder as PDF reports

## Data Quality and Validation Requirements

### Duplicate Detection
- **Scope**: Check against entire Claims table database (not just current import)
- **Logic**: Exact match on 6 fields (ClaimNumber + Check_Number + CheckRunDate + Provider + MemberName + Amount)
- **Action**: Skip duplicate, continue processing, generate report
- **Reporting**: Create duplicate interface for review, email notification

### Error Handling Requirements
- **Invalid Group_Number**: Claim references non-existent group in Groups table
- **Missing Required Fields**: Any required CSV field is empty/null
- **Invalid Data Types**: Non-numeric amounts, invalid dates
- **File Format Errors**: CSV parsing failures, encoding issues
- **Action**: Log errors, continue processing, generate error report

### Data Validation Rules
- ClaimAmount must be positive decimal
- Dates must be valid date format
- Group_Number must exist in Groups table
- ChargeType must be valid enumeration value

## Performance Requirements

### Volume Specifications
- **Weekly Claims**: 100,000 records
- **Client Count**: 300 groups
- **Processing Window**: Complete weekly cycle within 4 hours
- **Report Generation**: All client reports within 2 hours of invoice creation

### Scalability Requirements
- Database design must support 5x volume growth
- Import process must handle files up to 500,000 records
- Concurrent user access for duplicate/error review interfaces

## Security and Compliance Requirements

### Data Protection
- No PHI (Protected Health Information) exposure in interfaces
- Audit trail for all data changes
- Secure file handling for CSV imports
- Access controls for sensitive financial data

### Audit Requirements
- Log all import activities with timestamps
- Track all duplicate detections with details
- Record all invoice generations with amounts
- Maintain error logs for troubleshooting

## User Interface and User Experience Requirements

### User Roles and Access Patterns

#### Primary Users
1. **Finance Operations Staff** - Daily CSV processing and error resolution
2. **Finance Managers** - Weekly reporting and process oversight  
3. **IT Support** - System administration and troubleshooting
4. **Clients (Future Phase 2)** - Self-service report access

### Core User Interface Requirements

#### 1. Weekly Processing Workflow Interface
**Business Purpose**: Monitor the weekly CSV → Claims → FAS → Invoice → Reports pipeline

**User Stories**:
- "What's the status of this week's processing?"
- "Are there any errors blocking invoice generation?"
- "Which clients still need reports generated?"

**Interface Components**:
- **Processing Status Dashboard** - Real-time pipeline status with visual workflow indicators
- **Progress Indicators** - Step-by-step completion status (Import → Aggregate → Generate → Report)
- **Error Alert Panel** - Immediate visibility to blocking issues with priority levels
- **Processing History** - Previous weeks' results with performance metrics
- **Quick Actions** - Start processing, retry failed steps, generate reports

#### 2. Duplicate Claims Management Interface
**Business Purpose**: Review and resolve duplicate detections that block processing

**User Stories**:
- "Why was this claim marked as duplicate?"
- "Is this a real duplicate or should I override?"
- "What claims are similar to this one?"

**Interface Components**:
- **Duplicate Review Queue** - List of flagged claims requiring review with aging indicators
- **Side-by-Side Comparison View** - Original vs duplicate claim details with highlighted differences
- **Resolution Actions** - Override/Confirm duplicate status with audit trail
- **Bulk Resolution Tools** - Handle multiple duplicates efficiently with pattern recognition
- **Search and Filter** - Find duplicates by Group, Date Range, Provider, Amount

#### 3. Error Resolution Interface
**Business Purpose**: Handle import errors and data validation failures

**User Stories**:
- "What went wrong with this CSV import?"
- "Which claims failed validation and why?"
- "How do I fix and reprocess these errors?"

**Interface Components**:
- **Error Management Queue** - All unresolved import/validation errors with severity levels
- **Error Details View** - Specific validation failure reasons with suggested corrections
- **Data Correction Forms** - Edit invalid data with real-time validation feedback
- **Batch Reprocessing Controls** - Retry failed operations with progress tracking
- **Error Pattern Analysis** - Identify recurring issues for process improvement

#### 4. Data Management Interfaces
**Business Purpose**: Maintain master data and review processed transactions

**Interface Components**:

**4a. Groups Management Interface**
- **Groups Directory** - Searchable list of all client groups with status indicators
- **Group Profile Editor** - CRUD operations for client master data with validation
- **Group History View** - Processing volume and performance trends
- **Bulk Import Tools** - CSV import for group master data updates

**4b. Claims Browser Interface**
- **Advanced Search** - Filter by Group, Date Range, Provider, Amount, Status
- **Claims Grid View** - Sortable, paginated display with export capabilities
- **Claim Detail View** - Full claim information with audit trail and linked FAS/Invoice
- **Claims Analytics** - Volume trends, top providers, processing patterns

**4c. Invoice Management Interface**
- **Invoice Dashboard** - Generated invoices by date and group with status tracking
- **Invoice Detail View** - Complete invoice with linked Claims and FAS entries
- **Invoice Regeneration** - Reprocess invoices with changed business rules
- **Client Communication** - Email delivery status and download tracking

**4d. FAS Review Interface**
- **FAS Validation Dashboard** - Review financial aggregations before invoice generation
- **FAS Detail Drill-down** - Show underlying claims that created FAS entries
- **FAS Adjustment Tools** - Handle special cases and manual corrections
- **Reconciliation Reports** - Validate FAS totals against Claims data

#### 5. Reporting and Download Interface
**Business Purpose**: Generate and distribute client reports

**User Stories**:
- "Which clients need reports generated?"
- "Where can I download the PDF/Excel for Group ABC?"
- "Did all 300 client reports generate successfully?"

**Interface Components**:
- **Report Generation Dashboard** - Batch report creation status with progress indicators
- **Download Center** - Access completed PDF/Excel reports with search and filter
- **Report History** - Previous reporting periods with regeneration capabilities
- **Delivery Tracking** - Monitor report distribution and client access
- **Report Templates** - Manage PDF layouts and Excel formats

### User Experience Design Requirements

#### Performance Standards
- **Page Load Times** - < 3 seconds for all data views
- **Search Performance** - < 1 second for claims lookup with proper indexing
- **Bulk Operations** - Progress indicators for operations > 5 seconds
- **Responsive Design** - Full functionality on desktop, tablet, and mobile devices
- **Offline Capability** - Read-only access to recent data when connection is lost

#### Error Handling and User Guidance
- **Clear Error Messages** - Specific, actionable guidance with help links
- **Context Preservation** - Maintain user work during errors and system issues
- **Undo Capabilities** - Reverse accidental actions on critical operations
- **Contextual Help** - Integrated guidance and documentation
- **User Onboarding** - Progressive disclosure for new users

#### Data Volume Management
- **Smart Pagination** - Handle 100k+ records with efficient navigation
- **Advanced Filtering** - Multiple criteria with saved filter presets
- **Export Capabilities** - Download filtered datasets in multiple formats
- **Performance Optimization** - Lazy loading, client-side caching, progressive enhancement
- **Memory Management** - Efficient handling of large datasets without browser crashes

#### Security and Compliance UX
- **Audit Trail Visibility** - Clear "who changed what when" information
- **Access Control Indicators** - Visual cues for permission boundaries and restrictions
- **PHI Protection** - No sensitive health information exposure in any interface
- **Session Management** - Secure timeouts with work preservation and re-authentication
- **Data Masking** - Sensitive financial data protection with role-based visibility

#### Integration and Workflow Features
- **Email Notifications** - Configurable alerts for errors, completions, and exceptions
- **File Upload Interface** - Drag-and-drop CSV import with real-time validation feedback
- **Print-Friendly Views** - Professional layouts for reports and audit documentation
- **API Integration Points** - Future-ready interfaces for source system connections
- **Keyboard Shortcuts** - Power-user navigation for frequent operations

### Accessibility and Compliance Standards
- **WCAG 2.1 AA Compliance** - Screen reader compatibility and keyboard navigation
- **Color Contrast** - High contrast modes for visual accessibility
- **Font Scaling** - Support for user font size preferences
- **Language Support** - Interface localization readiness
- **Browser Compatibility** - Support for IE11+, Chrome, Firefox, Safari, Edge

### Mobile and Remote Access Requirements
- **Responsive Design** - Full functionality across device sizes
- **Touch Interfaces** - Optimized for tablet and mobile interaction
- **Offline Synchronization** - Queue actions for later processing when connectivity returns
- **Mobile-Specific Features** - Camera integration for document capture
- **Performance Optimization** - Minimized data usage and battery consumption

## Success Criteria

### Primary Success Measures
- **Data Accuracy**: 100% of valid claims processed correctly
- **Process Automation**: Eliminate manual Excel summary creation
- **Report Quality**: Professional PDF/Excel formats replace manual documents
- **Error Handling**: All duplicates and errors properly detected and reported
- **Performance**: Weekly processing completes within required timeframes

### Secondary Success Measures  
- **User Adoption**: Finance team actively uses new interfaces
- **Client Satisfaction**: Professional reports improve client experience
- **Operational Efficiency**: Reduced manual intervention and email questions
- **Scalability**: System handles volume growth without performance degradation

## Technical Implementation Specifications

### Database Platform Selection
**Chosen Platform**: PostgreSQL
**Rationale**: 
- Open source (no licensing costs vs. SQL Server's $3k-$15k annual fees)
- Enterprise-grade features and performance
- Advanced SQL capabilities and JSON support
- Strong security and compliance features
- Excellent analytical query performance for reporting

### Process Optimizations (SQL Expert Recommendations)
**A) Real-time Duplicate Detection**: Implemented during import process using staging table approach
**B) Automated Error Notification**: Auto-email duplicate reports while maintaining UI for error review
**C) Indexing Strategy**: Optimized for 100k weekly claims with composite indexes on duplicate detection fields

### Key Business Rules for Implementation
1. **NULL-based Processing**: Only process records where InvoiceID IS NULL (prevents double-billing)
2. **Audit Traceability**: Both Claims and FAS records linked to Invoice for complete audit trail
3. **Incremental Processing**: Failed processes can be rerun safely due to NULL-based filtering
4. **Duplicate Prevention**: 6-field exact match across entire Claims database history

## Future Enhancement Opportunities

### Phase 2 Considerations
- Real-time processing instead of weekly batches
- Client self-service portal for invoice/report access
- Integration with source claims system (eliminate CSV import)
- Additional charge types beyond "Paid"
- Automated payment processing integration

### Data Unlock Benefits
- Analytics team could use centralized claims data
- Other departments could benefit from client master data
- Compliance reporting could be automated
- Business intelligence and trend analysis capabilities

---

**Document Status**: Updated with SQL Expert clarifications - Ready for database design
**Next Step**: SQL Expert to create PostgreSQL schema and stored procedures
**Approval Required**: Business sponsor sign-off before development begins