-- mssql.srv.query.suspended.snapshot.Sql
--------- [BEG] Parameters ---------
DECLARE @iDoDetails BIT = 0;
DECLARE @iWaitTimeMs INT SET @iWaitTimeMs = 0;--15000;
DECLARE @iSQLPreviewLen INT SET @iSQLPreviewLen = 256;
--------- [END] Parameters ---------

--------- [BEG] Init ---------
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 10000;

IF OBJECT_ID(N'tempdb..#sys_dm_os_waiting_tasks_lck_tb') IS NOT NULL
	TRUNCATE TABLE #sys_dm_os_waiting_tasks_lck_tb;
ELSE
	CREATE TABLE #sys_dm_os_waiting_tasks_lck_tb
	(	waiting_task_address              VARBINARY(8) NOT NULL
	,	session_id                        SMALLINT NOT NULL
	,	exec_context_id                   INT NULL
	,	wait_duration_ms                  BIGINT NULL
	,	wait_type                         NVARCHAR(60) NULL
	,	resource_address                  VARBINARY(8) NULL
	,	blocking_task_address             VARBINARY(8) NULL
	,	blocking_session_id               SMALLINT NULL
	,	blocking_exec_context_id          INT NULL
	,	resource_description_ext          NVARCHAR(2048) NOT NULL
	,	request_mode                      NVARCHAR(60) NULL
	,	resource_type                     NVARCHAR(60) NULL
	,	resource_subtype                  NVARCHAR(60) NULL
	,	resource_database_id              INT NULL
	,	resource_description              NVARCHAR(256) NULL
	,	resource_associated_entity_id     BIGINT NULL)

IF	OBJECT_ID(N'tempdb..#request_blocked_tb') IS NOT NULL
	TRUNCATE TABLE #request_blocked_tb;
ELSE
	CREATE TABLE #request_blocked_tb
	(	[blocking_branch] [varchar](128) NOT NULL
	,	[session_id] [smallint] NOT NULL
	,	[database_id] [smallint] NOT NULL
	,	[request_id] [int] NULL
	,	[request_start_time] [datetime] NULL
	,	[request_end_time] [datetime] NULL
	,	[session_login_time] [datetime] NULL
	,	[session_host_name] [nvarchar](128) NULL
	,	[session_login_name] [nvarchar](128) NOT NULL
	,	[session_original_login_name] [nvarchar](128) NULL
	,	[session_program_name] [nvarchar](128) NULL
	,	[session_last_request_start_time] [datetime] NULL
	,	[session_last_request_end_time] [datetime] NULL
	,	[session_transaction_isolation_level] [smallint] NULL
	,	[blocking_session_id] [smallint] NULL
	,	[last_wait_type] [nvarchar](60) NULL
	,	[wait_type] [nvarchar](60) NOT NULL
	,	[wait_resource] [nvarchar](2048) NOT NULL
	,	[wait_time] [int] NOT NULL
	,	[command] [nvarchar](16) NOT NULL
	,	[sql_handle] [varbinary](64) NULL
	,	[stmt_start_offset] [int] NULL
	,	[stmt_end_offset] [int] NULL
	,	[plan_handle] [varbinary](64) NULL
	,	[batch_preview] [nvarchar](MAX) NULL
	,	[stmt_preview] [nvarchar](MAX) NULL
	);

IF	OBJECT_ID(N'tempdb..#session_locks_tb') IS NOT NULL
	TRUNCATE TABLE #session_locks_tb;
ELSE
BEGIN
	CREATE TABLE #session_locks_tb
	(	[resource_type] [nvarchar](60) NOT NULL,
		[resource_subtype] [nvarchar](60) NOT NULL,
		[resource_database_id] [int] NOT NULL,
		[resource_description] [nvarchar](256) NOT NULL,
		[resource_associated_entity_id] [bigint] NULL,
		[resource_database_name] [nvarchar](258) NULL,
		[resource_object_schema] [sysname] NULL,
		[resource_object_name] [sysname] NULL,
		[resource_object_type] [char](2) NULL,
		[resource_index_name] [sysname] NULL,
		[request_mode] [nvarchar](60) NOT NULL,
		[request_type] [nvarchar](60) NOT NULL,
		[request_status] [nvarchar](60) NOT NULL,
		[request_reference_count] [smallint] NOT NULL,
		[request_lifetime] [int] NOT NULL,
		[request_session_id] [int] NOT NULL,
		[request_session_login_time] [datetime] NULL,
		[request_request_id] [int] NOT NULL,
		[request_owner_type] [nvarchar](60) NOT NULL
	);
	
	CREATE NONCLUSTERED INDEX [#session_locks_resource_ix] 
		ON [dbo].[#session_locks_tb] ([resource_type],[resource_database_id]) 
		INCLUDE ([resource_associated_entity_id]);
END

--------- [END] Init ---------

DECLARE @SQLTSessionLockSpecializing AS NVARCHAR(4000) = N'
UPDATE tl SET 
	tl.resource_object_type = ob_pr.[type]
,	tl.resource_object_schema = sc_pr.name
,	tl.resource_object_name = ob_pr.name
,	tl.resource_index_name = ix_pr.name
FROM
	#session_locks_tb tl
INNER JOIN 
		?(dbq).sys.partitions pr
	INNER JOIN
		?(dbq).sys.indexes ix_pr
	ON	ix_pr.[object_id] = pr.[object_id]
	AND	ix_pr.[index_id] = pr.[index_id]
	INNER JOIN
		?(dbq).sys.objects ob_pr
	ON	ob_pr.[object_id] = pr.[object_id]
	INNER JOIN
		?(dbq).sys.schemas sc_pr
	ON	sc_pr.[schema_id] = ob_pr.[schema_id]
ON	pr.hobt_id = tl.resource_associated_entity_id
WHERE
	tl.resource_database_id = DB_ID(N?(dbrq))
AND	tl.resource_type IN (N''PAGE'', N''KEY'', N''RID'', N''HOBT'')
;

UPDATE tl SET 
	tl.resource_object_type = ob_apr.[type]
,	tl.resource_object_schema = sc_apr.name
,	tl.resource_object_name = ob_apr.name
,	tl.resource_index_name = ix_apr.name
FROM
	#session_locks_tb tl
INNER JOIN
		(	SELECT	_au.allocation_unit_id, _pr.object_id, _pr.index_id
			FROM	
				?(dbq).sys.allocation_units _au
			INNER JOIN
				?(dbq).sys.partitions _pr
			ON	_pr.hobt_id = _au.container_id
			AND	_au.type IN(1,3)
			AND	_pr.partition_number = 1
			AND _au.[type] = 1
			UNION ALL
			SELECT	_au.allocation_unit_id, _pr.object_id, _pr.index_id
			FROM	
				?(dbq).sys.allocation_units _au
			INNER JOIN
				?(dbq).sys.partitions _pr
			ON	_pr.partition_id = _au.container_id
			AND	_au.type = 2
			AND	_pr.partition_number = 1
			AND _au.[type] = 1
		) as apr
	INNER JOIN
		?(dbq).sys.indexes ix_apr
	ON	ix_apr.[object_id] = apr.[object_id]
	AND	ix_apr.[index_id] = apr.[index_id]
	INNER JOIN
		?(dbq).sys.objects ob_apr
	ON	ob_apr.[object_id] = ix_apr.[object_id]
	INNER JOIN
		?(dbq).sys.schemas sc_apr
	ON	sc_apr.[schema_id] = ob_apr.[schema_id]
ON	tl.resource_associated_entity_id =  apr.allocation_unit_id
WHERE
	tl.resource_database_id = DB_ID(N?(dbrq))
AND	tl.resource_type = N''ALLOCATION_UNIT''
;

UPDATE tl SET 
	tl.resource_object_type = ob.[type]
,	tl.resource_object_schema = sc.name
,	tl.resource_object_name = ob.name
FROM
	#session_locks_tb tl
INNER JOIN
		?(dbq).sys.objects ob
	INNER JOIN
		?(dbq).sys.schemas sc
	ON	ob.[schema_id] = sc.[schema_id] 
ON	tl.resource_associated_entity_id = ob.[object_id]
WHERE
	tl.resource_database_id = DB_ID(N?(dbrq))
AND	tl.resource_type = N''OBJECT'';

';

INSERT INTO #sys_dm_os_waiting_tasks_lck_tb
(	waiting_task_address, session_id, exec_context_id, wait_duration_ms, wait_type, resource_address, blocking_task_address, blocking_session_id, blocking_exec_context_id, resource_description_ext)
SELECT	
	waiting_task_address, session_id, exec_context_id, wait_duration_ms, wait_type, resource_address, blocking_task_address, blocking_session_id, blocking_exec_context_id, ISNULL(resource_description, N'')
FROM	sys.dm_os_waiting_tasks
WHERE	session_id IS NOT NULL;

IF NOT EXISTS
(	SELECT	*
 	FROM	#sys_dm_os_waiting_tasks_lck_tb
 	WHERE	
 		/* wait_type LIKE 'LCK[_]%' */
 		ISNULL(blocking_session_id, 0) <> 0
 	AND	wait_duration_ms >= @iWaitTimeMs
)	
	GOTO LB_PASS;

--!!!DBG: snapshot if somthing goes wrong
/* 
IF OBJECT_ID(N'tempdb..#sys_dm_exec_sessions') IS NOT NULL
	DROP TABLE #sys_dm_exec_sessions;

SELECT	*
INTO	#sys_dm_exec_sessions
FROM	sys.dm_exec_sessions; 
*/

TRUNCATE TABLE #request_blocked_tb;

INSERT INTO #request_blocked_tb
(	blocking_branch
,	session_id
,	database_id
,	request_id
,	blocking_session_id
,	request_start_time
,	session_login_time
,	session_host_name 
,	session_login_name
,	session_original_login_name
,	session_program_name
,	session_last_request_start_time
,	session_last_request_end_time 
,	session_transaction_isolation_level
,	last_wait_type
,	wait_type
,	wait_resource
,	wait_time
,	command
,	sql_handle
,	stmt_start_offset
,	stmt_end_offset
,	plan_handle
,	batch_preview 
,	stmt_preview)
SELECT	
	blocking_branch = CASE WHEN ISNULL(owt.blocking_session_id, 0) = 0 THEN RIGHT('   ' + CAST(es.session_id AS VARCHAR(11)), 4)  ELSE '' END
,	es.session_id
,	er.database_id
,	er.request_id
,	blocking_session_id = ISNULL(owt.blocking_session_id, 0)
,	request_start_time = er.start_time
,	session_login_time = es.login_time
,	session_host_name = es.[host_name]
,	session_login_name = es.[login_name]
,	session_original_login_name = es.[original_login_name]
,	session_program_name = es.program_name
,	session_last_request_start_time = es.last_request_start_time
,	session_last_request_end_time = es.last_request_end_time
,	session_transaction_isolation_level = es.transaction_isolation_level
,	last_wait_type = er.last_wait_type
,	wait_type     = CASE WHEN owt.session_id IS NOT NULL THEN ISNULL(owt.wait_type, N'')                ELSE ISNULL(er.wait_type, N'')     END
,	wait_resource = CASE WHEN owt.session_id IS NOT NULL THEN ISNULL(owt.resource_description, N'')     ELSE ISNULL(er.wait_resource, N'') END
,	wait_time     = CASE WHEN owt.session_id IS NOT NULL THEN ISNULL(owt.wait_duration_ms, N'')         ELSE ISNULL(er.wait_time, 0)       END
,	command = ISNULL(er.command, '')
,	er.sql_handle
,	stmt_start_offset = er.statement_start_offset
,	stmt_end_offset = er.statement_end_offset
,	er.plan_handle
,	[sql].batch_preview
,	[sql].stmt_preview
FROM		
	sys.dm_exec_sessions es
LEFT OUTER JOIN
	#sys_dm_os_waiting_tasks_lck_tb AS owt
ON	owt.session_id = es.session_id
LEFT OUTER JOIN
	sys.dm_exec_requests er
ON	es.session_id = er.session_id
OUTER APPLY
	(	SELECT	
			database_id = _sql.dbid
		,	object_id = _sql.objectid
		,	batch_preview = 
				CASE er.session_id 
					WHEN @@SPID THEN N'--</main-session>'
					ELSE CAST(SUBSTRING(_sql.[text], 1, @iSQLPreviewLen) AS NVARCHAR(4000))
				END
		,	stmt_preview = 
				CASE 
					WHEN er.statement_end_offset = er.statement_start_offset THEN
						NULL
					WHEN er.session_id = @@SPID THEN
						N'--</main-session>'
					WHEN er.statement_start_offset = 0 THEN
						N'--</batch>'
					WHEN er.statement_end_offset IS NULL
					OR	er.statement_end_offset < 0
					THEN
						CAST(SUBSTRING(_sql.[text], er.statement_start_offset / 2, @iSQLPreviewLen) AS NVARCHAR(4000)) 
					ELSE
						CAST(SUBSTRING(_sql.[text], er.statement_start_offset / 2, CASE WHEN ( er.statement_end_offset - er.statement_start_offset ) > @iSQLPreviewLen * 2 THEN @iSQLPreviewLen ELSE ( er.statement_end_offset - er.statement_start_offset ) / 2 END ) AS NVARCHAR(4000))
				END
		FROM	sys.dm_exec_sql_text(er.sql_handle) _sql	
	) AS [sql]
WHERE
	EXISTS
	(	SELECT	*
	 	FROM	#sys_dm_os_waiting_tasks_lck_tb AS _owtB
	 	WHERE	
	 		_owtB.session_id = es.session_id
	 	/*AND	_owtB.wait_type LIKE 'LCK[_]%'*/
		AND	ISNULL(_owtB.blocking_session_id, 0) <> 0
	 	OR	_owtB.blocking_session_id = es.session_id
	)
;

DECLARE @resource_description_ext nvarchar(2048) = N'';

DECLARE 
	@resource_type                     NVARCHAR(60)
,	@resource_subtype                  NVARCHAR(60)
,	@resource_database_id              INT
,	@resource_description              NVARCHAR(256)
,	@resource_associated_entity_id     BIGINT
,	@resource_lock_partition           INT
,	@request_mode                      NVARCHAR(60)
;

DECLARE @rdescr_attr_tb TABLE 
	(	[name] NVARCHAR(1024) NOT NULL
	,	[key_str] NVARCHAR(128) NOT NULL
	,	[pos] INT NULL
	,	[value] NVARCHAR(4000) NULL)
;

INSERT INTO @rdescr_attr_tb
(	[name], [key_str])
VALUES
(	N'id',                  N'id=lock')
,(	N'mode',                N'mode=')
,(	N'dbid',                N'dbid=')
,(	N'associatedObjectId',  N'associatedObjectId=')
,(	N'subresource',         N'subresource=')
,(	N'fileid',              N'fileid=')
,(	N'lockPartition',       N'lockPartition=')
,(	N'objid',               N'objid=')
,(	N'pageid',              N'pageid=')
,(	N'hobtid',              N'hobtid=')
,(	N'hash',                N'hash=')
,(	N'databasePrincipalId', N'databasePrincipalId=')
,(	N'classid',             N'classid=');

WHILE 1 = 1
BEGIN
	SELECT	TOP 1 
		@resource_description_ext = resource_description_ext
	FROM	#sys_dm_os_waiting_tasks_lck_tb
	WHERE	
		wait_type LIKE 'LCK[_]%'
	AND	resource_description_ext > @resource_description_ext
	ORDER BY resource_description_ext;
	
	IF @@ROWCOUNT < 1
		BREAK;
	
	PRINT @resource_description_ext;
	
	DECLARE @Pos INT, @PosNext INT, @Len INT;
	
	IF @resource_description_ext NOT LIKE N'%lock %'
	BEGIN
		RAISERROR('Parse error! Input string="%s"',11,1,@resource_description_ext)
		GOTO LB_PASS;	
	END;

	SET @Len = CHARINDEX(N'lock ', @resource_description_ext);
	SET @resource_type = UPPER(SUBSTRING(@resource_description_ext, 1, @Len - 1));
	SET @Pos = @Len + LEN(N'lock') + 1;

	IF EXISTS 
	(	SELECT	* 
		FROM	(VALUES (N'DATABASE') , (N'FILE') , (N'OBJECT') , (N'PAGE') , (N'KEY') , (N'EXTENT') , (N'RID') , (N'APPLICATION') , (N'METADATA') , (N'HOBT') , (N'ALLOCATION_UNIT')) t(f) 
		WHERE	t.f = @resource_type
	)
	BEGIN
		DECLARE
			@rdescr_attr_name NVARCHAR(1024)
		,	@rdescr_attr_value NVARCHAR(4000);

		UPDATE @rdescr_attr_tb SET
			pos = CASE WHEN CHARINDEX([key_str], @resource_description_ext, @Pos) > 0 THEN CHARINDEX([key_str], @resource_description_ext, @Pos) END
		;

		SET @PosNext = LEN(@resource_description_ext) + 1;

		SELECT TOP 1
			@Pos = pos 
		,	@Len = len(key_str)
		,	@rdescr_attr_name = name
		FROM	@rdescr_attr_tb
		WHERE	pos IS NOT NULL
		ORDER BY pos DESC;

		WHILE @@ROWCOUNT > 0
		BEGIN
			SET @rdescr_attr_value = substring(@resource_description_ext, @Pos + @Len, @PosNext - (@Pos + @Len));

			UPDATE @rdescr_attr_tb SET 
				[value] = @rdescr_attr_value
			WHERE	
				[name] =  @rdescr_attr_name 
			
			SET @PosNext = @Pos - 1;
	
			SELECT TOP 1
				@Pos = pos
			,	@Len = len(key_str)
			,	@rdescr_attr_name = name
			FROM	@rdescr_attr_tb
			WHERE
				pos IS NOT NULL
			AND	pos < @PosNext
			ORDER BY pos DESC;
		END;
		
		SET @request_mode = '';
		SEt @resource_subtype = '';
		
		SELECT	
			@resource_database_id          = CASE [name] WHEN 'dbid'                THEN CAST([value] AS SMALLINT) ELSE @resource_database_id END 
		,	@request_mode                  = CASE [name] WHEN 'mode'                THEN [value] ELSE @request_mode END
		,	@resource_associated_entity_id = CASE [name] WHEN 'associatedObjectId'  THEN CAST([value] AS BIGINT) ELSE @resource_associated_entity_id END
		,	@resource_subtype              = CASE [name] WHEN 'subresource'         THEN [value] ELSE @resource_subtype END
		FROM	@rdescr_attr_tb;

		SET @resource_description = '';

		SELECT	
			@resource_description          = CASE [name] WHEN 'fileid'              THEN  [value] + ':' + ISNULL(@resource_description,N'') ELSE @resource_description END 
		,	@resource_description          = CASE [name] WHEN 'pageid'              THEN  ISNULL(@resource_description, N'') + [value] ELSE @resource_description END 
		,	@resource_description          = CASE [name] WHEN 'classid'             THEN [value] ELSE @resource_description END 
		,	@resource_description          = CASE [name] WHEN 'hash'                THEN ISNULL(@resource_description, N'') + N'[' + SUBSTRING([value], 1, LEN([value]) - 8) + ']' ELSE @resource_description END
		,	@resource_description          = CASE [name] WHEN 'databasePrincipalId' THEN [value] + ':' + ISNULL(@resource_description, N'') ELSE @resource_description END
		FROM	@rdescr_attr_tb;

	
		UPDATE @rdescr_attr_tb SET pos = NULL, [value] = NULL;

		UPDATE #sys_dm_os_waiting_tasks_lck_tb SET
			request_mode = @request_mode
		,	resource_type = @resource_type
	--	,	resource_subtype = @resource_subtype
		,	resource_database_id = @resource_database_id
		,	resource_description = @resource_description
		,	resource_associated_entity_id = @resource_associated_entity_id 
		WHERE
			resource_description_ext = @resource_description_ext	
	END;
END;

TRUNCATE TABLE #session_locks_tb;

IF @iDoDetails = 1
	INSERT INTO #session_locks_tb
	(	resource_type
	,	resource_subtype
	,	resource_database_id
	,	resource_description
	,	resource_associated_entity_id
	,	resource_database_name
	,	request_mode
	,	request_type
	,	request_status
	,	request_reference_count
	,	request_lifetime
	,	request_session_id
	,	request_request_id
	,	request_owner_type)
	SELECT 
		tl.resource_type
	,	tl.resource_subtype
	,	tl.resource_database_id
	,	resource_description = RTRIM(tl.resource_description)
	,	tl.resource_associated_entity_id
	,	resource_database_name = DB_NAME(tl.resource_database_id)
	,	tl.request_mode
	,	tl.request_type
	,	tl.request_status
	,	tl.request_reference_count
	,	tl.request_lifetime
	,	tl.request_session_id
	,	tl.request_request_id
	,	tl.request_owner_type
	FROM
		sys.dm_tran_locks tl
	WHERE
		EXISTS 
		(	SELECT	*
			FROM	
				#sys_dm_os_waiting_tasks_lck_tb _owt
			WHERE
				(	_owt.session_id = tl.request_session_id
				AND	_owt.resource_type = tl.resource_type
				AND	tl.request_status <> N'GRANT')
			OR
				(	_owt.blocking_session_id = tl.request_session_id
				AND	(	tl.resource_type NOT IN (N'OBJECT', N'PAGE', N'KEY', N'RID', N'HOBT', N'ALLOCATION_UNIT') OR _owt.resource_associated_entity_id = _owt.resource_associated_entity_id)

				/*!!!REM: not tested
				AND	(	tl.resource_type IN (N'OBJECT', N'PAGE', N'KEY', N'RID', N'HOBT', N'ALLOCATION_UNIT') AND _owt.resource_associated_entity_id = _owt.resource_associated_entity_id
					OR	tl.resource_type = N'DATABASE'    AND tl.resource_database_id = _owt.resource_database_id
					OR	tl.resource_type = N'FILE'        AND tl.resource_database_id = _owt.resource_database_id AND tl.resource_description = _owt.resource_description 
					OR	tl.resource_type = N'EXTENT'      AND tl.resource_database_id = _owt.resource_database_id AND tl.resource_description = _owt.resource_description 
					OR	tl.resource_type = N'APPLICATION' AND tl.resource_database_id = _owt.resource_database_id AND tl.resource_description LIKE REPLACE(_owt.resource_description, N'[', N'[[]') + '%'
					OR	tl.resource_type = N'METADATA'    AND tl.resource_database_id = _owt.resource_database_id
					OR  tl.resource_type NOT IN (N'DATABASE', N'FILE', N'OBJECT', N'PAGE', N'KEY', N'EXTENT', N'RID', N'APPLICATION', N'METADATA', N'HOBT', N'ALLOCATION_UNIT')
					)
				*/
				)
		)
	;
ELSE
	INSERT INTO #session_locks_tb
	(	resource_type
	,	resource_subtype
	,	resource_database_id
	,	resource_description
	,	resource_associated_entity_id
	,	resource_database_name
	,	request_mode
	,	request_type
	,	request_status
	,	request_reference_count
	,	request_lifetime
	,	request_session_id
	,	request_request_id
	,	request_owner_type)
	SELECT 
		resource_type = ISNULL(owt.resource_type, N'')
	,	resource_subtype = ISNULL(owt.resource_subtype, N'')
	,	owt.resource_database_id
	,	resource_description = ISNULL(owt.resource_description, '')
	,	owt.resource_associated_entity_id
	,	resource_database_name = DB_NAME(owt.resource_database_id)
	,	owt.request_mode
	,	request_type = ''
	,	request_status = N'WAIT'
	,	request_reference_count = 0
	,	request_lifetime = ISNULL(owt.wait_duration_ms, 0)
	,	request_session_id = owt.session_id
	,	request_request_id = 0
	,	request_owner_type = 'SESSION'
	FROM
		#sys_dm_os_waiting_tasks_lck_tb owt
	WHERE
		owt.wait_type LIKE 'LCK[_]%'
	;

DECLARE @DBName_tb TABLE 
(	[id] SMALLINT NOT NULL, [name] SYSNAME NOT NULL);

INSERT INTO @DBName_tb
(	[id], [name])
SELECT	DISTINCT
	resource_database_id
,	resource_database_name
FROM	#session_locks_tb
WHERE	resource_database_name IS NOT NULL;

DECLARE @SQL AS NVARCHAR(4000);
DECLARE @DBName AS NVARCHAR(4000);
DECLARE @DBId AS INT;
	
SELECT	TOP 1
	@DBName = [name]
,	@DBId = id
FROM	@DBName_tb
WHERE	EXISTS (SELECT * FROM sys.databases _db WHERE _db.database_id = id AND _db.[state] = 0)
ORDER BY [id];

WHILE @@ROWCOUNT > 0
BEGIN
	SET @SQL = @SQLTSessionLockSpecializing;
	SET @SQL = REPLACE(REPLACE(@SQL, N'?(dbrq)', QUOTENAME(@DBName, '''')), N'?(dbq)', QUOTENAME(@DBName));
				
	--PRINT @SQL;
	EXEC (@SQL);
			
	SELECT	TOP 1
		@DBName = [name]
	,	@DBId = id
	FROM	@DBName_tb
	WHERE	
		[id] > @DBId
	AND	EXISTS (SELECT * FROM sys.databases _db WHERE _db.database_id = id AND _db.[state] = 0)
	ORDER BY [id];			
END;

/* !!!DBG: if something wrong near "INSERT INTO #request_blocked_tb" .
UPDATE #request_blocked_tb SET
	blocking_branch = CASE WHEN ISNULL(blocking_session_id, 0) = 0 THEN SUBSTRING('   ' + CAST(session_id AS VARCHAR(11)), 1, 6)  ELSE '' END;  
*/
WHILE 1=1
BEGIN	
	UPDATE rb_dst SET
		blocking_branch = rb_src.blocking_branch + '<' 
	FROM
		#request_blocked_tb rb_dst 
	INNER JOIN
		#request_blocked_tb rb_src
	ON	rb_src.session_id = rb_dst.blocking_session_id
	WHERE	
		rb_src.blocking_branch <> ''
	AND	rb_dst.blocking_branch = ''
	
	IF @@ROWCOUNT < 1 BREAK;
END;

SELECT
	blocking_branch
,	session_id
,	blocking_session_id
,	waits = 
		CASE 
			WHEN wait_type IS NULL THEN
				N'*' + last_wait_type
			WHEN wait_type IS NOT NULL AND ISNULL(wait_resource, '') <> '' THEN
				wait_type + N'(' + [wait_resource] + N')'
			WHEN wait_type IS NOT NULL AND ISNULL(wait_resource, '') = '' THEN
				wait_type
		END 
,	wait_time = RIGHT('0' + CAST([wait_time]/24/60/60/1000 AS VARCHAR(11)), 2) + ' ' + CONVERT(VARCHAR, DATEADD(ms, [wait_time]%(24*60*60*1000), CAST('00:00:00' AS TIME(3))), 14)
,	database_name = db_name(database_id)
,	session_program_name
,	request_id
,	request_start_time
,	session_login_time
,	session_host_name
,	session_login_name
,	session_original_login_name
,	session_transaction_isolation_level
,	command
,	batch_preview
,	stmt_preview
,	[sql_handle]
,	stmt_start_offset
,	stmt_end_offset
,	[plan_handle]
FROM
	#request_blocked_tb
ORDER BY	
	blocking_branch
,	session_id;

SELECT
	resource_type
,	resource_subtype
,	resource_database_id
,	resource_description
,	resource_associated_entity_id
,	resource_database_name
,	resource_object_type
,	resource_object_schema
,	resource_object_name
,	resource_index_name
,	request_mode
,	request_type
,	request_status
,	request_reference_count
,	request_lifetime
,	request_session_id
,	request_session_login_time
,	request_request_id
,	request_owner_type
FROM	#session_locks_tb;

GOTO LB_EXIT;

LB_PASS: 
PRINT 'pass'
--WAITFOR DELAY '00:00:05';
LB_EXIT:
GO 
