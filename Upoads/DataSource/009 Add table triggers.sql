-- ******************************************************
-- Add table triggers.
-- ******************************************************
PRINT '';
PRINT '*** Creating Table Triggers';
GO

CREATE TRIGGER [HumanResources].[dEmployee] ON [HumanResources].[Employee]
INSTEAD OF DELETE NOT FOR REPLICATION AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    BEGIN
        RAISERROR
            (N'Employees cannot be deleted. They can only be marked as not current.', -- Message
            10, -- Severity.
            1); -- State.

        -- Rollback any active or uncommittable transactions
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END
    END;
END;
GO

CREATE TRIGGER [Person].[iuPerson] ON [Person].[Person]
AFTER INSERT, UPDATE NOT FOR REPLICATION AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    IF UPDATE([BusinessEntityID]) OR UPDATE([Demographics])
    BEGIN
        UPDATE [Person].[Person]
        SET [Person].[Person].[Demographics] = N'<IndividualSurvey xmlns="http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey">
            <TotalPurchaseYTD>0.00</TotalPurchaseYTD>
            </IndividualSurvey>'
        FROM inserted
        WHERE [Person].[Person].[BusinessEntityID] = inserted.[BusinessEntityID]
            AND inserted.[Demographics] IS NULL;
       
        UPDATE [Person].[Person]
        SET [Demographics].modify(N'declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey";
            insert <TotalPurchaseYTD>0.00</TotalPurchaseYTD>
            as first
            into (/IndividualSurvey)[1]')
        FROM inserted
        WHERE [Person].[Person].[BusinessEntityID] = inserted.[BusinessEntityID]
            AND inserted.[Demographics] IS NOT NULL
            AND inserted.[Demographics].exist(N'declare default element namespace
                "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey";
                /IndividualSurvey/TotalPurchaseYTD') <> 1;
    END;
END;
GO

CREATE TRIGGER [Purchasing].[iPurchaseOrderDetail] ON [Purchasing].[PurchaseOrderDetail]
AFTER INSERT AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO [Production].[TransactionHistory]
            ([ProductID]
            ,[ReferenceOrderID]
            ,[ReferenceOrderLineID]
            ,[TransactionType]
            ,[TransactionDate]
            ,[Quantity]
            ,[ActualCost])
        SELECT
            inserted.[ProductID]
            ,inserted.[PurchaseOrderID]
            ,inserted.[PurchaseOrderDetailID]
            ,'P'
            ,GETDATE()
            ,inserted.[OrderQty]
            ,inserted.[UnitPrice]
        FROM inserted
            INNER JOIN [Purchasing].[PurchaseOrderHeader]
            ON inserted.[PurchaseOrderID] = [Purchasing].[PurchaseOrderHeader].[PurchaseOrderID];

        -- Update SubTotal in PurchaseOrderHeader record. Note that this causes the
        -- PurchaseOrderHeader trigger to fire which will update the RevisionNumber.
        UPDATE [Purchasing].[PurchaseOrderHeader]
        SET [Purchasing].[PurchaseOrderHeader].[SubTotal] =
            (SELECT SUM([Purchasing].[PurchaseOrderDetail].[LineTotal])
                FROM [Purchasing].[PurchaseOrderDetail]
                WHERE [Purchasing].[PurchaseOrderHeader].[PurchaseOrderID] = [Purchasing].[PurchaseOrderDetail].[PurchaseOrderID])
        WHERE [Purchasing].[PurchaseOrderHeader].[PurchaseOrderID] IN (SELECT inserted.[PurchaseOrderID] FROM inserted);
    END TRY
    BEGIN CATCH
        EXECUTE [dbo].[uspPrintError];

        -- Rollback any active or uncommittable transactions before
        -- inserting information in the ErrorLog
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXECUTE [dbo].[uspLogError];
    END CATCH;
END;
GO

CREATE TRIGGER [Purchasing].[uPurchaseOrderDetail] ON [Purchasing].[PurchaseOrderDetail]
AFTER UPDATE AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    BEGIN TRY
        IF UPDATE([ProductID]) OR UPDATE([OrderQty]) OR UPDATE([UnitPrice])
        -- Insert record into TransactionHistory
        BEGIN
            INSERT INTO [Production].[TransactionHistory]
                ([ProductID]
                ,[ReferenceOrderID]
                ,[ReferenceOrderLineID]
                ,[TransactionType]
                ,[TransactionDate]
                ,[Quantity]
                ,[ActualCost])
            SELECT
                inserted.[ProductID]
                ,inserted.[PurchaseOrderID]
                ,inserted.[PurchaseOrderDetailID]
                ,'P'
                ,GETDATE()
                ,inserted.[OrderQty]
                ,inserted.[UnitPrice]
            FROM inserted
                INNER JOIN [Purchasing].[PurchaseOrderDetail]
                ON inserted.[PurchaseOrderID] = [Purchasing].[PurchaseOrderDetail].[PurchaseOrderID];

            -- Update SubTotal in PurchaseOrderHeader record. Note that this causes the
            -- PurchaseOrderHeader trigger to fire which will update the RevisionNumber.
            UPDATE [Purchasing].[PurchaseOrderHeader]
            SET [Purchasing].[PurchaseOrderHeader].[SubTotal] =
                (SELECT SUM([Purchasing].[PurchaseOrderDetail].[LineTotal])
                    FROM [Purchasing].[PurchaseOrderDetail]
                    WHERE [Purchasing].[PurchaseOrderHeader].[PurchaseOrderID]
                        = [Purchasing].[PurchaseOrderDetail].[PurchaseOrderID])
            WHERE [Purchasing].[PurchaseOrderHeader].[PurchaseOrderID]
                IN (SELECT inserted.[PurchaseOrderID] FROM inserted);

            UPDATE [Purchasing].[PurchaseOrderDetail]
            SET [Purchasing].[PurchaseOrderDetail].[ModifiedDate] = GETDATE()
            FROM inserted
            WHERE inserted.[PurchaseOrderID] = [Purchasing].[PurchaseOrderDetail].[PurchaseOrderID]
                AND inserted.[PurchaseOrderDetailID] = [Purchasing].[PurchaseOrderDetail].[PurchaseOrderDetailID];
        END;
    END TRY
    BEGIN CATCH
        EXECUTE [dbo].[uspPrintError];

        -- Rollback any active or uncommittable transactions before
        -- inserting information in the ErrorLog
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXECUTE [dbo].[uspLogError];
    END CATCH;
END;
GO

CREATE TRIGGER [Purchasing].[uPurchaseOrderHeader] ON [Purchasing].[PurchaseOrderHeader]
AFTER UPDATE AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    BEGIN TRY
        -- Update RevisionNumber for modification of any field EXCEPT the Status.
        IF NOT UPDATE([Status])
        BEGIN
            UPDATE [Purchasing].[PurchaseOrderHeader]
            SET [Purchasing].[PurchaseOrderHeader].[RevisionNumber] =
                [Purchasing].[PurchaseOrderHeader].[RevisionNumber] + 1
            WHERE [Purchasing].[PurchaseOrderHeader].[PurchaseOrderID] IN
                (SELECT inserted.[PurchaseOrderID] FROM inserted);
        END;
    END TRY
    BEGIN CATCH
        EXECUTE [dbo].[uspPrintError];

        -- Rollback any active or uncommittable transactions before
        -- inserting information in the ErrorLog
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXECUTE [dbo].[uspLogError];
    END CATCH;
END;
GO

CREATE TRIGGER [Sales].[iduSalesOrderDetail] ON [Sales].[SalesOrderDetail]
AFTER INSERT, DELETE, UPDATE AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    BEGIN TRY
        -- If inserting or updating these columns
        IF UPDATE([ProductID]) OR UPDATE([OrderQty]) OR UPDATE([UnitPrice]) OR UPDATE([UnitPriceDiscount])
        -- Insert record into TransactionHistory
        BEGIN
            INSERT INTO [Production].[TransactionHistory]
                ([ProductID]
                ,[ReferenceOrderID]
                ,[ReferenceOrderLineID]
                ,[TransactionType]
                ,[TransactionDate]
                ,[Quantity]
                ,[ActualCost])
            SELECT
                inserted.[ProductID]
                ,inserted.[SalesOrderID]
                ,inserted.[SalesOrderDetailID]
                ,'S'
                ,GETDATE()
                ,inserted.[OrderQty]
                ,inserted.[UnitPrice]
            FROM inserted
                INNER JOIN [Sales].[SalesOrderHeader]
                ON inserted.[SalesOrderID] = [Sales].[SalesOrderHeader].[SalesOrderID];

            UPDATE [Person].[Person]
            SET [Demographics].modify('declare default element namespace
                "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey";
                replace value of (/IndividualSurvey/TotalPurchaseYTD)[1]
                with data(/IndividualSurvey/TotalPurchaseYTD)[1] + sql:column ("inserted.LineTotal")')
            FROM inserted
                INNER JOIN [Sales].[SalesOrderHeader] AS SOH
                ON inserted.[SalesOrderID] = SOH.[SalesOrderID]
                INNER JOIN [Sales].[Customer] AS C
                ON SOH.[CustomerID] = C.[CustomerID]
            WHERE C.[PersonID] = [Person].[Person].[BusinessEntityID];
        END;

        -- Update SubTotal in SalesOrderHeader record. Note that this causes the
        -- SalesOrderHeader trigger to fire which will update the RevisionNumber.
        UPDATE [Sales].[SalesOrderHeader]
        SET [Sales].[SalesOrderHeader].[SubTotal] =
            (SELECT SUM([Sales].[SalesOrderDetail].[LineTotal])
                FROM [Sales].[SalesOrderDetail]
                WHERE [Sales].[SalesOrderHeader].[SalesOrderID] = [Sales].[SalesOrderDetail].[SalesOrderID])
        WHERE [Sales].[SalesOrderHeader].[SalesOrderID] IN (SELECT inserted.[SalesOrderID] FROM inserted);

        UPDATE [Person].[Person]
        SET [Demographics].modify('declare default element namespace
            "http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/IndividualSurvey";
            replace value of (/IndividualSurvey/TotalPurchaseYTD)[1]
            with data(/IndividualSurvey/TotalPurchaseYTD)[1] - sql:column("deleted.LineTotal")')
        FROM deleted
            INNER JOIN [Sales].[SalesOrderHeader]
            ON deleted.[SalesOrderID] = [Sales].[SalesOrderHeader].[SalesOrderID]
            INNER JOIN [Sales].[Customer]
            ON [Sales].[Customer].[CustomerID] = [Sales].[SalesOrderHeader].[CustomerID]
        WHERE [Sales].[Customer].[PersonID] = [Person].[Person].[BusinessEntityID];
    END TRY
    BEGIN CATCH
        EXECUTE [dbo].[uspPrintError];

        -- Rollback any active or uncommittable transactions before
        -- inserting information in the ErrorLog
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXECUTE [dbo].[uspLogError];
    END CATCH;
END;
GO

CREATE TRIGGER [Sales].[uSalesOrderHeader] ON [Sales].[SalesOrderHeader]
AFTER UPDATE NOT FOR REPLICATION AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    BEGIN TRY
        -- Update RevisionNumber for modification of any field EXCEPT the Status.
        IF NOT UPDATE([Status])
        BEGIN
            UPDATE [Sales].[SalesOrderHeader]
            SET [Sales].[SalesOrderHeader].[RevisionNumber] =
                [Sales].[SalesOrderHeader].[RevisionNumber] + 1
            WHERE [Sales].[SalesOrderHeader].[SalesOrderID] IN
                (SELECT inserted.[SalesOrderID] FROM inserted);
        END;

        -- Update the SalesPerson SalesYTD when SubTotal is updated
        IF UPDATE([SubTotal])
        BEGIN
            DECLARE @StartDate datetime,
                    @EndDate datetime

            SET @StartDate = [dbo].[ufnGetAccountingStartDate]();
            SET @EndDate = [dbo].[ufnGetAccountingEndDate]();

            UPDATE [Sales].[SalesPerson]
            SET [Sales].[SalesPerson].[SalesYTD] =
                (SELECT SUM([Sales].[SalesOrderHeader].[SubTotal])
                FROM [Sales].[SalesOrderHeader]
                WHERE [Sales].[SalesPerson].[BusinessEntityID] = [Sales].[SalesOrderHeader].[SalesPersonID]
                    AND ([Sales].[SalesOrderHeader].[Status] = 5) -- Shipped
                    AND [Sales].[SalesOrderHeader].[OrderDate] BETWEEN @StartDate AND @EndDate)
            WHERE [Sales].[SalesPerson].[BusinessEntityID]
                IN (SELECT DISTINCT inserted.[SalesPersonID] FROM inserted
                    WHERE inserted.[OrderDate] BETWEEN @StartDate AND @EndDate);

            -- Update the SalesTerritory SalesYTD when SubTotal is updated
            UPDATE [Sales].[SalesTerritory]
            SET [Sales].[SalesTerritory].[SalesYTD] =
                (SELECT SUM([Sales].[SalesOrderHeader].[SubTotal])
                FROM [Sales].[SalesOrderHeader]
                WHERE [Sales].[SalesTerritory].[TerritoryID] = [Sales].[SalesOrderHeader].[TerritoryID]
                    AND ([Sales].[SalesOrderHeader].[Status] = 5) -- Shipped
                    AND [Sales].[SalesOrderHeader].[OrderDate] BETWEEN @StartDate AND @EndDate)
            WHERE [Sales].[SalesTerritory].[TerritoryID]
                IN (SELECT DISTINCT inserted.[TerritoryID] FROM inserted
                    WHERE inserted.[OrderDate] BETWEEN @StartDate AND @EndDate);
        END;
    END TRY
    BEGIN CATCH
        EXECUTE [dbo].[uspPrintError];

        -- Rollback any active or uncommittable transactions before
        -- inserting information in the ErrorLog
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXECUTE [dbo].[uspLogError];
    END CATCH;
END;
GO

CREATE TRIGGER [Purchasing].[dVendor] ON [Purchasing].[Vendor]
INSTEAD OF DELETE NOT FOR REPLICATION AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @DeleteCount int;

        SELECT @DeleteCount = COUNT(*) FROM deleted;
        IF @DeleteCount > 0
        BEGIN
            RAISERROR
                (N'Vendors cannot be deleted. They can only be marked as not active.', -- Message
                10, -- Severity.
                1); -- State.

        -- Rollback any active or uncommittable transactions
            IF @@TRANCOUNT > 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END;
    END TRY
    BEGIN CATCH
        EXECUTE [dbo].[uspPrintError];

        -- Rollback any active or uncommittable transactions before
        -- inserting information in the ErrorLog
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXECUTE [dbo].[uspLogError];
    END CATCH;
END;
GO

CREATE TRIGGER [Production].[iWorkOrder] ON [Production].[WorkOrder]
AFTER INSERT AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO [Production].[TransactionHistory](
            [ProductID]
            ,[ReferenceOrderID]
            ,[TransactionType]
            ,[TransactionDate]
            ,[Quantity]
            ,[ActualCost])
        SELECT
            inserted.[ProductID]
            ,inserted.[WorkOrderID]
            ,'W'
            ,GETDATE()
            ,inserted.[OrderQty]
            ,0
        FROM inserted;
    END TRY
    BEGIN CATCH
        EXECUTE [dbo].[uspPrintError];

        -- Rollback any active or uncommittable transactions before
        -- inserting information in the ErrorLog
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXECUTE [dbo].[uspLogError];
    END CATCH;
END;
GO

CREATE TRIGGER [Production].[uWorkOrder] ON [Production].[WorkOrder]
AFTER UPDATE AS
BEGIN
    DECLARE @Count int;

    SET @Count = @@ROWCOUNT;
    IF @Count = 0
        RETURN;

    SET NOCOUNT ON;

    BEGIN TRY
        IF UPDATE([ProductID]) OR UPDATE([OrderQty])
        BEGIN
            INSERT INTO [Production].[TransactionHistory](
                [ProductID]
                ,[ReferenceOrderID]
                ,[TransactionType]
                ,[TransactionDate]
                ,[Quantity])
            SELECT
                inserted.[ProductID]
                ,inserted.[WorkOrderID]
                ,'W'
                ,GETDATE()
                ,inserted.[OrderQty]
            FROM inserted;
        END;
    END TRY
    BEGIN CATCH
        EXECUTE [dbo].[uspPrintError];

        -- Rollback any active or uncommittable transactions before
        -- inserting information in the ErrorLog
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXECUTE [dbo].[uspLogError];
    END CATCH;
END;
GO
