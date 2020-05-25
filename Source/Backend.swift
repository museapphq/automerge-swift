//
//  File.swift
//  
//
//  Created by Lukas Schmidt on 07.04.20.
//

import Foundation

public protocol Backend {

    func applyLocalChange(request: Request) -> (Backend, Patch)

    func save() -> [UInt8]

    func getPatch() -> Patch

    func getChanges() -> [[UInt8]]
    
}

public final class RSBackend: Backend {

    private let automerge: OpaquePointer
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public convenience init() {
        self.init(automerge: automerge_init())
    }

    public convenience init(data: [UInt8]) {
        self.init(automerge: automerge_load(UInt(data.count), data))
    }

    public convenience init(changes: [[UInt8]]) {
        let newAutomerge = automerge_init()
        for change in changes {
            automerge_write_change(newAutomerge, UInt(change.count), change)
        }
        automerge_load_changes(newAutomerge)
        self.init(automerge: newAutomerge!)
    }

    init(automerge: OpaquePointer) {
        self.automerge = automerge
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = .prettyPrinted
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .custom({ (date, encoder) throws in
            var container = encoder.singleValueContainer()
            let seconds: UInt = UInt(date.timeIntervalSince1970)
            try container.encode(seconds)
        })
        decoder.dateDecodingStrategy = .custom({ (decoder) throws in
            var container = try decoder.unkeyedContainer()
            return try Date(timeIntervalSince1970: container.decode(TimeInterval.self))
        })
    }

    deinit {
        automerge_free(automerge)
    }

    public func save() -> [UInt8] {
        let length = automerge_save(automerge)
        var data = Array<UInt8>(repeating: 0, count: length)
        automerge_read_binary(automerge, &data)

        return data
    }

    public func applyLocalChange(request: Request) -> (Backend, Patch) {
        let data = try! encoder.encode(request)
        let string = String(data: data, encoding: .utf8)
        let length = automerge_apply_local_change(automerge, string)
        var buffer = Array<Int8>(repeating: 0, count: length)
        buffer.append(0)
        automerge_read_json(automerge, &buffer)
        let newString = String(cString: buffer)
        let patch = try! decoder.decode(Patch.self, from: newString.data(using: .utf8)!)

        return (RSBackend(automerge: automerge_clone(automerge)), patch)
    }

    public func getPatch() -> Patch {
        let length = automerge_get_patch(automerge)
        var buffer = Array<Int8>(repeating: 0, count: length)
        buffer.append(0)
        automerge_read_json(automerge, &buffer)
        let newString = String(cString: buffer)
        let patch = try! decoder.decode(Patch.self, from: newString.data(using: .utf8)!)

        return patch
    }

    public func getChanges() -> [[UInt8]] {
        var resut = [[UInt8]]()
        var len = automerge_get_changes(automerge, 0, nil);
        while (len > 0) {
            var data = Array<UInt8>(repeating: 0, count: len)
            len = automerge_read_binary(automerge, &data)
            resut.append(data)
        }

        return resut
    }
}

