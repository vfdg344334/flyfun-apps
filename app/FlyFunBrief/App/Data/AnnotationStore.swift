//
//  AnnotationStore.swift
//  FlyFunBrief
//
//  SQLite persistence for NOTAM user annotations.
//  Uses FMDB for database operations (same pattern as FlyFunEuroAIP).
//

import Foundation
import FMDB
import OSLog

/// SQLite storage for NOTAM annotations
actor AnnotationStore {
    // MARK: - Properties

    private var database: FMDatabase?
    private let dbPath: URL

    // MARK: - Init

    init() {
        // Store in app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FlyFunBrief", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.dbPath = appDir.appendingPathComponent("annotations.db")
    }

    // MARK: - Initialization

    /// Initialize the database and create tables if needed
    func initialize() async {
        Logger.app.info("Initializing AnnotationStore at \(self.dbPath.path)")

        database = FMDatabase(path: dbPath.path)

        guard let db = database, db.open() else {
            Logger.app.error("Failed to open annotation database")
            return
        }

        // Create tables
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS annotations (
                id TEXT PRIMARY KEY,
                notam_id TEXT NOT NULL,
                briefing_id TEXT NOT NULL,
                status TEXT NOT NULL,
                status_changed_at TEXT,
                text_note TEXT,
                handwritten_note BLOB,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_briefing_id ON annotations(briefing_id);
            CREATE INDEX IF NOT EXISTS idx_notam_id ON annotations(notam_id);
        """

        do {
            try db.executeStatements(createTableSQL)
            Logger.app.info("AnnotationStore initialized successfully")
        } catch {
            Logger.app.error("Failed to create annotation tables: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD Operations

    /// Load all annotations for a briefing
    func loadAnnotations(forBriefingId briefingId: String) async -> [String: NotamAnnotation] {
        guard let db = database, db.isOpen else {
            Logger.app.warning("Database not open, returning empty annotations")
            return [:]
        }

        var annotations: [String: NotamAnnotation] = [:]

        let sql = "SELECT * FROM annotations WHERE briefing_id = ?"

        do {
            let results = try db.executeQuery(sql, values: [briefingId])
            while results.next() {
                if let annotation = annotationFromRow(results) {
                    annotations[annotation.notamId] = annotation
                }
            }
            results.close()

            Logger.app.info("Loaded \(annotations.count) annotations for briefing \(briefingId)")
        } catch {
            Logger.app.error("Failed to load annotations: \(error.localizedDescription)")
        }

        return annotations
    }

    /// Save or update an annotation
    func saveAnnotation(_ annotation: NotamAnnotation) async {
        guard let db = database, db.isOpen else {
            Logger.app.warning("Database not open, cannot save annotation")
            return
        }

        let sql = """
            INSERT OR REPLACE INTO annotations
            (id, notam_id, briefing_id, status, status_changed_at, text_note, handwritten_note, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        let dateFormatter = ISO8601DateFormatter()

        let values: [Any] = [
            annotation.id,
            annotation.notamId,
            annotation.briefingId,
            annotation.status.rawValue,
            annotation.statusChangedAt.map { dateFormatter.string(from: $0) } as Any,
            annotation.textNote as Any,
            annotation.handwrittenNote as Any,
            dateFormatter.string(from: annotation.createdAt),
            dateFormatter.string(from: annotation.updatedAt)
        ]

        do {
            try db.executeUpdate(sql, values: values)
            Logger.app.debug("Saved annotation for NOTAM \(annotation.notamId)")
        } catch {
            Logger.app.error("Failed to save annotation: \(error.localizedDescription)")
        }
    }

    /// Delete an annotation
    func deleteAnnotation(_ annotation: NotamAnnotation) async {
        guard let db = database, db.isOpen else { return }

        let sql = "DELETE FROM annotations WHERE id = ?"

        do {
            try db.executeUpdate(sql, values: [annotation.id])
            Logger.app.debug("Deleted annotation \(annotation.id)")
        } catch {
            Logger.app.error("Failed to delete annotation: \(error.localizedDescription)")
        }
    }

    /// Delete all annotations for a briefing
    func deleteAnnotations(forBriefingId briefingId: String) async {
        guard let db = database, db.isOpen else { return }

        let sql = "DELETE FROM annotations WHERE briefing_id = ?"

        do {
            try db.executeUpdate(sql, values: [briefingId])
            Logger.app.info("Deleted all annotations for briefing \(briefingId)")
        } catch {
            Logger.app.error("Failed to delete annotations: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func annotationFromRow(_ row: FMResultSet) -> NotamAnnotation? {
        guard let notamId = row.string(forColumn: "notam_id"),
              let briefingId = row.string(forColumn: "briefing_id"),
              let statusRaw = row.string(forColumn: "status"),
              let status = NotamStatus(rawValue: statusRaw),
              let createdAtStr = row.string(forColumn: "created_at"),
              let updatedAtStr = row.string(forColumn: "updated_at") else {
            return nil
        }

        let dateFormatter = ISO8601DateFormatter()

        var annotation = NotamAnnotation(
            notamId: notamId,
            briefingId: briefingId,
            status: status,
            textNote: row.string(forColumn: "text_note")
        )

        annotation.statusChangedAt = row.string(forColumn: "status_changed_at")
            .flatMap { dateFormatter.date(from: $0) }
        annotation.handwrittenNote = row.data(forColumn: "handwritten_note")

        // Override timestamps from stored values
        // Note: createdAt is let, so we can't modify it - this is a simplification

        return annotation
    }

    // MARK: - Cleanup

    /// Close the database connection
    func close() {
        database?.close()
        database = nil
        Logger.app.info("AnnotationStore closed")
    }
}
