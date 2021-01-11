//
//  InviteProvider.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 23/04/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class InviteService {
	
	public struct PendingInvitation : CKRecordDecodable, CKRecordIdentifiable {
		public var saveState: CKRecordState = .local
		
		#warning("I don't think this should be public")
		public enum CloudKitKeys : String {
			case shareURL
			case guestIdentity
		}
		
		public static var recordType: String {
			return "Invite"
		}
		
		public init(cloudKitRecord: CKRecord) {
			url = URL(string: cloudKitRecord[CloudKitKeys.shareURL.rawValue] as! String)!
			guestIdentity = cloudKitRecord[CloudKitKeys.guestIdentity.rawValue] as! String
		}
		
		public let url: URL
		public let guestIdentity: String
	}
	
	public func fetch(name: String, completion: @escaping (Result<[PendingInvitation], Error>) -> Void)  {
		#warning("We should be using PendingInvitation.CloudKitKeys.guestIdentity.rawValue here, but it's giving me an error.")
		
		/*
		
		2020-05-08 22:37:45.949754-0500 Amazing Stories[4898:1486123] *** Terminating app due to uncaught exception 'CKException', reason: 'Invalid predicate: "guestIdentity" == "_58a2c26c38f4cc92924bddc440a0d327" (Error Domain=CKErrorDomain Code=12 "Invalid left expression in <"guestIdentity" == "_58a2c26c38f4cc92924bddc440a0d327">: <"guestIdentity"> is not an evaluated object expression" UserInfo={ck_isComparisonError=true, NSLocalizedDescription=Invalid left expression in <"guestIdentity" == "_58a2c26c38f4cc92924bddc440a0d327">: <"guestIdentity"> is not an evaluated object expression, NSUnderlyingError=0x282cb5da0 {Error Domain=CKErrorDomain Code=12 "<"guestIdentity"> is not an evaluated object expression" UserInfo={NSLocalizedDescription=<"guestIdentity"> is not an evaluated object expression, ck_isComparisonError=true}}})'
		*** First throw call stack:
		(0x2039e698c 0x202bbf9f8 0x20e11f208 0x20e11ebe0 0x231425940 0x10497c42c 0x1049839f0 0x104219ba8 0x104219d18 0x104267eb4 0x104219280 0x10421960c 0x10421a464 0x10421a508 0x10421c0c0 0x104146250 0x1049fb6f4 0x1049fcc78 0x104a0df1c 0x104a0e7ac 0x2036061b4 0x203608cd4)
		libc++abi.dylib: terminating with uncaught exception of type CKException
		
		*/
		
		let predicate = NSPredicate(format: "guestIdentity == %@", name)
		publicDatabase.read.fetch(predicate: predicate) { (result: Result<[PendingInvitation], Error>) in
			completion(result)
		}
	}
	
	public func accept(url: URL, completion: @escaping (Result<Bool, AcceptShareError>) -> Void)  {
		
		let fetchMetadataOperation = CKFetchShareMetadataOperation(shareURLs: [url])
		fetchMetadataOperation.perShareMetadataBlock = { _, possibleMetadata, error in
			
			guard error == nil else {
				
				let ckError = error! as! CKError
				if ckError.code == .unknownItem {
					completion(.failure(.invalidStateNoErrorButNoShareEither))
					return
				}
				
				completion(.failure(.cloudKit(error!)))
				return
			}
			
			guard let shareMetadata = possibleMetadata else {
				completion(.failure(.invalidStateNoMetadata))
				return
			}
			
			self.acceptShare(metadata: shareMetadata,
							 completion: completion)
		}
		
		self.container.add(fetchMetadataOperation)
	}
	
	public func ignore(recordID: CKRecord.ID, completion: @escaping (Result<Bool, AcceptShareError>) -> Void) {
		
		let saveOperation = CKModifyRecordsOperation(recordsToSave: nil,
													 recordIDsToDelete: [recordID])
		saveOperation.qualityOfService = .userInitiated
		saveOperation.modifyRecordsCompletionBlock = { possibleGroupAndShare, _, possibleSaveGroupAndShareError in
			
			guard possibleSaveGroupAndShareError == nil else {
				completion(.failure(.invalidStateNoErrorButNoShareEither))
				return
			}
			
			guard let records = possibleGroupAndShare, records.isEmpty else {
				completion(.failure(.invalidStateNoErrorButNoShareEither))
				return
			}
			
			completion(.success(true))
		}
		
		self.container.publicCloudDatabase.add(saveOperation)
	}
	
	public func send(record: CKRecord,
					 with participants: [CKUserIdentity],
					 completion: @escaping (Result<CKShare, ShareError>) -> Void) {
		
		let share = CKShare(rootRecord: record)
		
		// Transform users into share participants.
		let usersLookupInfo = participants.compactMap { $0.lookupInfo }
		let fetchParticipantsOperation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: usersLookupInfo)
		fetchParticipantsOperation.qualityOfService = .userInitiated
		fetchParticipantsOperation.shareParticipantFetchedBlock = { participant in
			participant.permission = .readWrite
			share.addParticipant(participant)
		}
		
		fetchParticipantsOperation.fetchShareParticipantsCompletionBlock = { possibleFetchParticipantsError in
			
			guard possibleFetchParticipantsError == nil else {
				completion(.failure(.cloudKit(possibleFetchParticipantsError!)))
				return
			}
			
			// We have the fetch participants.
			// Add them to the record by saving the record and the share at the same time.
			let saveOperation = CKModifyRecordsOperation(recordsToSave: [record, share])
			saveOperation.qualityOfService = .userInitiated
			saveOperation.modifyRecordsCompletionBlock = { possibleGroupAndShare, _, possibleSaveGroupAndShareError in
				
				guard possibleSaveGroupAndShareError == nil else {
					completion(.failure(.cloudKit(possibleSaveGroupAndShareError!)))
					return
				}
				
				guard let records = possibleGroupAndShare else {
					completion(.failure(.invalidStateNoRecordsWhileSavingShare))
					return
				}
				
				// The record has been shared. Get the acceptance URL.
				let share = records.compactMap({ $0 as? CKShare }).first!
				guard let shareURL = share.url else {
					completion(.failure(.invalidStateNoShareURL))
					return
				}
				
				// Create our invite records.
				let publicInvites = participants
					.compactMap { $0.userRecordID?.recordName }
					.filter { $0 != "__defaultOwner__" }
					.map { userRecordName -> CKRecord in
						let publicInvite = CKRecord(recordType: "Invite")
						publicInvite[PendingInvitation.CloudKitKeys.shareURL.rawValue] = shareURL.absoluteString
						publicInvite[PendingInvitation.CloudKitKeys.guestIdentity.rawValue] = userRecordName as CKRecordValue
						return publicInvite
				}
				
				guard !publicInvites.isEmpty else {
					completion(.failure(.missingUserIDs))
					return
				}
				
				// Publish them.
				let makeURLPublicOperation = CKModifyRecordsOperation(recordsToSave: publicInvites, recordIDsToDelete: nil)
				makeURLPublicOperation.qualityOfService = .userInitiated
				makeURLPublicOperation.modifyRecordsCompletionBlock = { possiblePublicInvites, _, possiblePublicInvitesError in
					
					guard possiblePublicInvitesError == nil else {
						completion(.failure(.cloudKit(possiblePublicInvitesError!)))
						return
					}
					
					#warning("We need to validate that all invites were sent out.")
					guard possiblePublicInvites != nil else {
						completion(.failure(.invalidStateNoRecordsWhileSavingInvites))
						return
					}
					
					// We've pushed the records to the database.
					completion(.success(share))
				}
				
				self.container.publicCloudDatabase.add(makeURLPublicOperation)
			}
			
			self.container.privateCloudDatabase.add(saveOperation)
		}
		
		self.container.add(fetchParticipantsOperation)
	}
	
	init(container: CKContainer) {
		self.container = container
		self.publicDatabase = AmazingZone(database: container.publicCloudDatabase,
										  zoneID: CKRecordZone.default().zoneID)
	}
	
	private let container: CKContainer
	private let publicDatabase: AmazingZone
}

// MARK: - Enums and associated objects
extension InviteService {
	
	public struct Invite {
		public let recordToShare: CKRecord
		public let participants: [CKUserIdentity]
		public let container: CKContainer
		
		public let publicInviteRecordID: CKRecord.ID
		public let shareURL: URL
		
		public fileprivate(set) var accepted: AcceptedStatus
		
		public enum AcceptedStatus : Equatable {
			case pendingRemoval
			case recordNotRemoved(Error)
			case recordPossiblyRemoved
			case recordRemoved
			
			public static func == (lhs: AcceptedStatus, rhs: AcceptedStatus) -> Bool {
				switch (lhs, rhs) {
				case (.pendingRemoval, .pendingRemoval),
					 (.recordPossiblyRemoved, .recordPossiblyRemoved),
					 (.recordRemoved, .recordRemoved):
					return true
					
				case (.recordNotRemoved(let lhsError), .recordNotRemoved(let rhsError)):
					return lhsError.localizedDescription == rhsError.localizedDescription
					
				default:
					return false
				}
			}
		}
	}
	
	public enum AcceptShareError : Error {
		case cloudKit(Error)
		case invalidStateNoMetadata
		case invalidStateNoErrorButNoShareEither
	}
	
	public enum ShareError : Error {
		case cloudKit(Error)
		case invalidStateNoRecordsWhileSavingShare
		case invalidStateNoShareURL
		case publicInvitesFailed(Error)
		case missingUserIDs
		case invalidStateNoRecordsWhileSavingInvites
	}
}

// MARK: - Private/Other
extension InviteService {
	
	private func acceptShare(metadata: CKShare.Metadata, completion: @escaping (Result<Bool, AcceptShareError>) -> Void) {
		
		let acceptShareOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
		acceptShareOperation.qualityOfService = .userInitiated
		acceptShareOperation.acceptSharesCompletionBlock = { possibleError in
			
			guard possibleError == nil else {
				
				// CKError: "Unknown Item" (11/2003); server message = "Share not found"
				// Have we already accepted this share?
				if (possibleError! as NSError).code == 11 {
					completion(.success(true))
					return
				}
				
				completion(.failure(.cloudKit(possibleError!)))
				return
			}
			
			let predicate = NSPredicate(format: "shareURL == %@", metadata.share.url!.absoluteString)
			self.publicDatabase.read.fetch(predicate: predicate) { (result: Result<[PendingInvitation], Error>) in
				
				switch result {
				case .success(let invitations):
					
					self.ignore(recordID: invitations.first!.saveState.backingRecord!.recordID,
								completion: completion)
					
				case .failure(let error):
					completion(.failure(.cloudKit(error)))
					
				}
			}
		}
		
		self.container.add(acceptShareOperation)
	}
}
