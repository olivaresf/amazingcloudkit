//
//  CKAcceptShareCoordinator.swift
//  Amazing Humans
//
//  Created by Fernando Olivares on 12/26/19.
//  Copyright © 2019 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class CKAcceptShareCoordinator {
	
	let publicInviteRecordID: CKRecord.ID
	let shareURL: URL
	let container: CKContainer
	public init(shareURL: URL, publicInviteRecordID: CKRecord.ID, container: CKContainer) {
		self.shareURL = shareURL
		self.publicInviteRecordID = publicInviteRecordID
		self.container = container
	}
	
	public enum AcceptShareError : LocalizedError {
        case cloudKit(Error)
		case invalidStateNoMetadata
        case invalidStateNoErrorButNoShareEither
		case invalidStateNoRecordRemovalConfirmation
		case invalidStateRecordNotRemoved
    }
}

// MARK: - Accepting Invites
public extension CKAcceptShareCoordinator {
	
	func acceptShare() throws {
		
		let shareMetadata: CKShare.Metadata
		do {
			shareMetadata = try metadata(from: shareURL)
		} catch let error as AcceptShareError {
			switch error {
				
			case .cloudKit(let ckError):
				// CKError: "Unknown Item" (11/2003); server message = "Share not found"
				if (ckError as NSError).code == 11 {
					try remove(publicInvite: publicInviteRecordID)
				}
				
				fallthrough
				
			case .invalidStateNoErrorButNoShareEither,
				 .invalidStateNoMetadata,
				 .invalidStateNoRecordRemovalConfirmation,
				 .invalidStateRecordNotRemoved:
				throw error
			}
		} catch {
			throw error
		}
		
		try accept(using: shareMetadata)
		
		try remove(publicInvite: publicInviteRecordID)
	}
	
	private func metadata(from shareURL: URL) throws -> CKShare.Metadata {
		
		return try await(asyncExecutionBlock: { (awaitCompletion: @escaping (Result<CKShare.Metadata, AcceptShareError>) -> Void) in
			let fetchMetadataOperation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
			fetchMetadataOperation.qualityOfService = .userInitiated
			fetchMetadataOperation.perShareMetadataBlock = { _, possibleMetadata, error in
				guard error == nil else {
					awaitCompletion(.failure(.cloudKit(error!)))
					return
				}
				
				guard let shareMetadata = possibleMetadata else {
					awaitCompletion(.failure(.invalidStateNoMetadata))
					return
				}
				
				awaitCompletion(.success(shareMetadata))
			}
			
			self.container.add(fetchMetadataOperation)
		})
    }
    
	@discardableResult
    private func accept(using metadata: CKShare.Metadata) throws -> Bool {
		
		return try await(asyncExecutionBlock: { (awaitCompletion: @escaping (Result<Bool, AcceptShareError>) -> Void) in
			
			let acceptShareOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
			acceptShareOperation.qualityOfService = .userInitiated
			acceptShareOperation.acceptSharesCompletionBlock = { possibleError in
				
				guard possibleError == nil else {
					awaitCompletion(.failure(.cloudKit(possibleError!)))
					return
				}
				
				awaitCompletion(.success(true))
			}
			
			self.container.add(acceptShareOperation)
		})
	}
	
	@discardableResult
	private func remove(publicInvite: CKRecord.ID) throws -> Bool  {
		
		return try await(asyncExecutionBlock: { (awaitCompletion: @escaping (Result<Bool, AcceptShareError>) -> Void) in
			
			let saveOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [publicInvite])
			saveOperation.qualityOfService = .userInitiated
			saveOperation.modifyRecordsCompletionBlock = { possibleGroupAndShare, _, possibleSaveGroupAndShareError in
				
				guard possibleSaveGroupAndShareError == nil else {
					awaitCompletion(.failure(.cloudKit(possibleSaveGroupAndShareError!)))
					return
				}
				
				guard let records = possibleGroupAndShare else {
					awaitCompletion(.failure(.invalidStateNoRecordRemovalConfirmation))
					return
				}
				
				guard records.isEmpty else {
					awaitCompletion(.failure(.invalidStateRecordNotRemoved))
					return
				}
				
				awaitCompletion(.success(true))
			}
			
			self.container.publicCloudDatabase.add(saveOperation)
		})
	}
}

