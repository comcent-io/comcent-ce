-- Transfer data from cost column to price column for records before 27-06-2025
UPDATE "OrgAuditLog"
SET "price" = "cost"
WHERE "createdAt" < '2025-06-27 00:00:00';
