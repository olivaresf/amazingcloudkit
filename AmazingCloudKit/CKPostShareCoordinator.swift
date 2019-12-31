//
//  CKPostShareCoordinator.swift
//  Amazing Humans
//
//  Created by Fernando Olivares on 12/17/19.
//  Copyright © 2019 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class CKPostShareCoordinator {
	
	let record: CKRecord
	let participants: [CKUserIdentity]
	let container: CKContainer
	public init(record: CKRecord, participants: [CKUserIdentity], container: CKContainer) {
		self.record = record
		self.participants = participants
		self.container = container
	}
	
	public enum ShareError : Error {
		case cloudKit(Error)
		case invalidStateNoRecordsWhileSavingShare
		case invalidStateNoShareURL
		case publicInvitesFailed(Error)
		case missingUserIDs
		case invalidStateNoRecordsWhileSavingInvites
	}
	
	public enum FetchMetadataError : LocalizedError {
        case cloudKit(Error)
        case invalidStateNoMetadata
    }
	
	public enum AcceptShareError : LocalizedError {
        case cloudKit(Error)
        case invalidStateNoErrorButNoShareEither
    }
	
	public enum RemoveRecordError : LocalizedError {
		case cloudKit(Error)
		case invalidStateNoRecordRemovalConfirmation
		case invalidStateRecordNotRemoved
	}
}

// MARK: - Sending Invites
public extension CKPostShareCoordinator {
	
	func publishInvites() throws -> [CKRecord] {
		
		// Create a CKShare with the given record and participants.
		let savedShare = try createShare()
		
		// We have a share now. Save it and its root record so we can get the acceptance URL.
		let savedShareURL = try saveShare(share: savedShare)
		
		// Each participant will be "tagged" in an invite that contains the acceptance URL.
		return try createInvites(shareURL: savedShareURL)
	}
	
	private func createShare() throws -> CKShare {
		
		return try await { (awaitCompletion: @escaping (Result<CKShare, ShareError>) -> Void) in
			
			let share = CKShare(rootRecord: self.record)
			
			// Transform users into share participants.
			let usersLookupInfo = self.participants.compactMap { $0.lookupInfo }
			let fetchParticipantsOperation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: usersLookupInfo)
			fetchParticipantsOperation.qualityOfService = .userInitiated
			fetchParticipantsOperation.shareParticipantFetchedBlock = { participant in
				participant.permission = .readWrite
				share.addParticipant(participant)
			}
			fetchParticipantsOperation.fetchShareParticipantsCompletionBlock = { possibleFetchParticipantsError in
				if let fetchParticipantsError = possibleFetchParticipantsError {
					awaitCompletion(.failure(.cloudKit(fetchParticipantsError)))
				}
				
				awaitCompletion(.success(share))
			}
			
			self.container.add(fetchParticipantsOperation)
		}
	}
	
	private func saveShare(share: CKShare) throws -> URL {
		
		return try await { (awaitCompletion:  @escaping (Result<URL, ShareError>) -> Void) in
			
			let saveOperation = CKModifyRecordsOperation(recordsToSave: [self.record, share], recordIDsToDelete: nil)
			saveOperation.qualityOfService = .userInitiated
			saveOperation.modifyRecordsCompletionBlock = { possibleGroupAndShare, _, possibleSaveGroupAndShareError in
				
				guard possibleSaveGroupAndShareError == nil else {
					awaitCompletion(.failure(.cloudKit(possibleSaveGroupAndShareError!)))
					return
				}
				
				guard let records = possibleGroupAndShare else {
					awaitCompletion(.failure(.invalidStateNoRecordsWhileSavingShare))
					return
				}
				
				// Get the URL out of the share.
				let share = records.compactMap({ $0 as? CKShare }).first!
				guard let shareURL = share.url else {
					awaitCompletion(.failure(.invalidStateNoShareURL))
					return
				}
				
				awaitCompletion(.success(shareURL))
			}
			
			self.container.privateCloudDatabase.add(saveOperation)
		}
	}
	
	private func createInvites(shareURL: URL) throws -> [CKRecord] {
		
		return try await(asyncExecutionBlock: { (awaitCompletion: @escaping (Result<[CKRecord], ShareError>) -> Void) in
		
			let publicInvites = self.participants
				.compactMap { $0.userRecordID?.recordName }
				.filter { $0 != "__defaultOwner__" }
				.map { userRecordName -> CKRecord in
					let publicInvite = CKRecord(recordType: "Invite")
					publicInvite["shareURL"] = shareURL.absoluteString
					publicInvite["shareeIdentity"] = userRecordName as CKRecordValue
					return publicInvite
			}
			
			guard !publicInvites.isEmpty else {
			awaitCompletion(.failure(.missingUserIDs))
				return
			}
		
			let makeURLPublicOperation = CKModifyRecordsOperation(recordsToSave: publicInvites, recordIDsToDelete: nil)
			makeURLPublicOperation.qualityOfService = .userInitiated
			makeURLPublicOperation.modifyRecordsCompletionBlock = { possiblePublicInvites, _, possiblePublicInvitesError in
				
				guard possiblePublicInvitesError == nil else {
					awaitCompletion(.failure(.cloudKit(possiblePublicInvitesError!)))
					return
				}
				
				guard let publicInvites = possiblePublicInvites else {
					awaitCompletion(.failure(.invalidStateNoRecordsWhileSavingInvites))
					return
				}
				
				awaitCompletion(.success(publicInvites))
			}
			
			self.container.publicCloudDatabase.add(makeURLPublicOperation)
		})
	}
}
