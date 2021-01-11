//
//  CKRecordConvertible.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 16/05/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public typealias CKRecordConvertible = CKRecordIdentifiable & CKRecordDecodable & CKRecordEncodable

public enum CKRecordState {
	case local
	case unsaved(backingRecord: CKRecord, zoneName: ZoneName)
	case saved(backingRecord: CKRecord, zoneName: ZoneName)
	
	public var backingRecord: CKRecord? {
		switch self {
			
		case .local:
			return nil
			
		case .unsaved(let backingRecord, _),
			 .saved(let backingRecord, _):
			return backingRecord
		}
	}
	
	public var zoneName: ZoneName? {
		switch self {
			
		case .local:
			return nil
			
		case .unsaved(_, let zoneName),
			 .saved(_, let zoneName):
			return zoneName
		}
	}
}

extension CKRecordState : Codable {
	
	enum CodingError : Error {
		case decodingFromCorruptedObject
	}
	
	enum CodingKeys : CodingKey {
		case backingRecord
		case zoneName
		case intValue
	}
	
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		
		let intValue = try container.decode(Int.self, forKey: .intValue)
		if intValue == 0 {
			self = .local
		} else if intValue == 1 || intValue == 2 {
	
			let zoneName = try container.decode(String.self, forKey: .zoneName)
			
			// Unwrap the CKRecord
			let backingRecordData = try container.decode(Data.self, forKey: .backingRecord)
			let possibleBackingRecord = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: backingRecordData)
			let backingRecord = try possibleBackingRecord.unwrap()
			
			if intValue == 1 {
				self = .saved(backingRecord: backingRecord,
							  zoneName: zoneName)
			} else {
				self = .unsaved(backingRecord: backingRecord,
								zoneName: zoneName)
			}
			
		} else {
			throw CodingError.decodingFromCorruptedObject
		}
		
		
	}
	
	public func encode(to encoder: Encoder) throws {
		
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(intValue, forKey: .intValue)
		
		switch self {
			
		case .local:
			break
		
		case .saved(let backingRecord, let zone),
			 .unsaved(let backingRecord, let zone):
			let backingRecordData = try NSKeyedArchiver.archivedData(withRootObject: backingRecord,
																	 requiringSecureCoding: true)
			
			try container.encode(backingRecordData, forKey: .backingRecord)
			try container.encode(zone, forKey: .zoneName)
		}
	}
	
	private var intValue: Int {
		switch self {
		case .local: return 0
		case .saved: return 1
		case .unsaved: return 2
		}
	}
}

public protocol CKRecordIdentifiable {
	static var recordType: String { get }
}

public protocol CKRecordDecodable {
	
	// Transforms a fetched CKRecord to a CKRecordDecodable object/struct.
	init(cloudKitRecord: CKRecord)
	
	// Self-explanatory
	var saveState: CKRecordState { get set }
}

public protocol CKRecordEncodable {
	// Transforms a CKRecordEncodable object/struct to a CKRecord.
	func convert(to record: CKRecord)
}
