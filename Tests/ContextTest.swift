//
//  File.swift
//  
//
//  Created by Lukas Schmidt on 17.04.20.
//

import Foundation
import XCTest
@testable import Automerge

final class Spion<T> {
    private (set) var value: T?
    private (set) var callCount = 0

    var observer: (T) -> Void {
        return {
            self.value = $0
            self.callCount += 1
        }
    }
}

extension Spion where T == ObjectDiff {

    var observerDiff: (T, Object?, inout [ObjectId: Object]) -> Object? {
        return { diff, _, _ in
            self.observer(diff)
            return nil
        }
    }

}

class ContextTest: XCTestCase {

    var applyPatch: Spion<ObjectDiff>!

    override func setUp() {
        super.setUp()
        applyPatch = Spion()
    }

    // should assign a primitive value to a map key
    func testContextSetMapKey1() {
        // GIVEN
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [.root: .map(Map(objectId: "", mapValues: [:], conflicts: [:]))],
            ops: []
        )

        // WHEN
        context.setMapKey(path: [], key: "sparrows", value: 5.0)

        // THEN
        XCTAssertEqual(context.ops, [Op(action: .set, obj: .root, key: "sparrows", value: 5.0)])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
                        objectId: .root,
                        type: .map,
                        props: [
                            "sparrows": [actor.actorId: .value(.init(value: 5.0,
                                                                     datatype: nil))]])
        )
    }

    // should do nothing if the value was not changed
    func testContextSetMapKey2() {
        //Given
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [
                .root: .map(Map(
                                objectId: .root,
                                mapValues: ["goldfinches": 3.0],
                                conflicts: ["goldfinches": ["actor1": 3.0]])
                )
            ],
            ops: []
        )
        // WHEN
        context.setMapKey(path: [], key: "goldfinches", value: 3.0)

        //THEN
        XCTAssertEqual(context.ops, [])
        XCTAssertNil(applyPatch.value)
        XCTAssertEqual(applyPatch.callCount, 0)
    }

    // should allow a conflict to be resolved
    func testContextSetMapKey3() {
        //Given
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [
                .root: .map(Map(
                    objectId: .root,
                    mapValues: ["goldfinches": 5.0],
                    conflicts: ["goldfinches": ["actor1": 3.0, "actor2": 5.0]]

                ))
            ],
            ops: [])
        // WHEN
        context.setMapKey(path: [], key: "goldfinches", value: 3.0)

        //THEN
        XCTAssertEqual(context.ops, [Op(action: .set, obj: .root, key: "goldfinches", value: 3.0)])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(objectId: .root,
                                                    type: .map,
                                                    props: [
                                                        "goldfinches": [actor.actorId: 3.0]]))
    }

    //should create nested maps
    func testContextSetMapKey4() {
        // GIVEN
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [.root: .map(Map(objectId: ""))],
            ops: []
        )

        // WHEN
        context.setMapKey(path: [], key: "birds", value: .map(Map(objectId: "", mapValues: ["goldfinches": 3.0])))

        let objectId = applyPatch.value!.props!["birds"]![actor.actorId]!.objectId!
        XCTAssertEqual(context.ops, [
            Op(action: .makeMap, obj: .root, key: "birds", child: objectId),
            Op(action: .set, obj: objectId, key: "goldfinches", value: 3.0)
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            props: [
                "birds": [actor.actorId: .object(.init(
                    objectId: objectId,
                    type: .map,
                    props: [
                        "goldfinches": [actor.actorId: 3.0]]
                ))
                ]
            ]
        )
        )
    }

    // should perform assignment inside nested maps
    func testContextSetMapKey5() {
        let actor = Actor()
        let objectId = ObjectId()
        let child: Object = .map(Map(objectId: objectId))
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [
                objectId: child,
                .root: .map(Map(objectId: .root, mapValues: ["birds": child], conflicts: ["birds": ["actor1": child]]))
            ])

        // WHEN
        context.setMapKey(path: [.init(key: "birds", objectId: objectId)], key: "goldfinches", value: 3.0)

        //THEN
        XCTAssertEqual(context.ops, [Op(action: .set, obj: objectId, key: "goldfinches", value: 3.0)])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            edits: nil,
            props: [
                "birds": ["actor1": .object(.init(
                    objectId: objectId,
                    type: .map,
                    props: [
                        "goldfinches": [actor.actorId: 3.0]]
                ))
                ]
            ]
        )
        )
    }

    // should perform assignment inside conflicted maps
    func testContextSetMapKey6() {
        //Given
        let actor = Actor()
        let objectId1 = ObjectId()
        let child1: Object = .map(Map(objectId: objectId1))
        let objectId2 = ObjectId()
        let child2: Object = .map(Map(objectId: objectId2))
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [
                objectId1: child1,
                objectId2: child2,
                .root: .map(Map(
                                objectId: .root,
                                mapValues: ["birds": child2],
                                conflicts: ["birds": [
                                    "actor1": child1,
                                    "actor2": child2
                                ]])
                )
            ])

        //When
        context.setMapKey(path: [.init(key: "birds", objectId: objectId2)], key: "goldfinches", value: 3.0)

        //Then
        XCTAssertEqual(context.ops, [Op(action: .set, obj: objectId2, key: "goldfinches", value: 3.0)])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            edits: nil,
            props: [
                "birds": [
                    "actor1": .object(.init(objectId: objectId1, type: .map)),
                    "actor2": .object(.init(
                        objectId: objectId2,
                        type: .map,
                        props: [
                            "goldfinches": [actor.actorId: 3.0]
                        ]
                    ))
                ]
            ]
        )
        )
    }

    // should handle conflict values of various types
    func testContextSetMapKey7() {
        // Given
        let actor = Actor()
        let objectId = ObjectId()
        let child: Object = .map(Map(objectId: objectId))
        let dateValue = Date()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [
                objectId: child,
                .root: .map(Map(
                                objectId: .root,
                                mapValues: ["values": child],
                                conflicts: ["values": [
                                    "actor1": .date(dateValue),
                                    "actor2": .counter(0),
                                    "actor3": 42.0,
                                    "actor4": .primitive(.null),
                                    "actor5": child
                                ]])
                )
            ])
        //When
        context.setMapKey(path: [.init(key: "values", objectId: objectId)], key: "goldfinches", value: 3.0)

        //Then
        XCTAssertEqual(context.ops, [Op(action: .set, obj: objectId, key: "goldfinches", value: 3.0)])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            edits: nil,
            props: [
                "values": [
                    "actor1": .value(.init(value: .number(dateValue.timeIntervalSince1970), datatype: .timestamp)),
                    "actor2": .value(.init(value: 0.0, datatype: .counter)),
                    "actor3": 42.0,
                    "actor4": .value(.init(value: .null)),
                    "actor5": .object(.init(objectId: objectId, type: .map, props: ["goldfinches": [actor.actorId: 3.0]]))
                ]
            ]
        )
        )
    }

    // should create nested lists
    func testContextSetMapKey8() {
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [.root: .map(.init(objectId: ""))],
            ops: []
        )
        // WHEN
        context.setMapKey(path: [], key: "birds", value: .list(List(objectId: "", listValues: ["sparrow", "goldfinch"], conflicts: [])))

        // Then
        let objectId = applyPatch.value!.props!["birds"]![actor.actorId]!.objectId!
        XCTAssertEqual(context.ops, [
            Op(action: .makeList, obj: .root, key: "birds", child: objectId),
            Op(action: .set, obj: objectId, key: 0, insert: true, value: .string("sparrow")),
            Op(action: .set, obj: objectId, key: 1, insert: true, value: .string("goldfinch"))
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            props: [
                "birds": [
                    actor.actorId: .object(.init(objectId: objectId,
                                                 type: .list,
                                                 edits: [Edit(action: .insert, index: 0), Edit(action: .insert, index: 1)],
                                                 props: [
                                                    0: [actor.actorId: "sparrow"],
                                                    1: [actor.actorId: "goldfinch"]
                                                 ]))
                ]
            ]
        )
        )
    }

    // should create nested Text objects
    func testContextSetMapKey9() {
        //Given
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [.root: .map(.init(objectId: ""))],
            ops: []
        )
        // WHEN
        context.setMapKey(path: [], key: "text", value: .text(Text("hi")))

        //THEN
        let objectId = applyPatch.value!.props!["text"]![actor.actorId]!.objectId!
        XCTAssertEqual(context.ops, [
            Op(action: .makeText, obj: .root, key: "text", child: objectId),
            Op(action: .set, obj: objectId, key: .index(0), insert: true, value: .string("h")),
            Op(action: .set, obj: objectId, key: .index(1), insert: true, value: .string("i"))
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            props: [
                "text": [
                    actor.actorId: .object(.init(objectId: objectId,
                                                 type: .text,
                                                 edits: [Edit(action: .insert, index: 0), Edit(action: .insert, index: 1)],
                                                 props: [
                                                    0: [actor.actorId: "h"],
                                                    1: [actor.actorId: "i"]
                                                 ]))
                ]
            ]
        )
        )
    }

    // should create nested Table objects
    func testContextSetMapKey10() {
        //Given
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [.root: .map(.init(objectId: ""))],
            ops: []
        )
        // WHEN
        context.setMapKey(path: [], key: "books", value: .table(Table(tableValues: [:], objectId: "")))

        //Then
        let objectId = applyPatch.value!.props!["books"]![actor.actorId]!.objectId!
        XCTAssertEqual(context.ops, [
            Op(action: .makeTable, obj: .root, key: "books", child: objectId)
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            props: [
                "books": [
                    actor.actorId: .object(.init(objectId: objectId, type: .table, props: [:]))
                ]
            ]
        )
        )
    }

    // should allow assignment of Date values
    func testContextSetMapKey11() {
        //Given
        let now = Date()
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [.root: .map(.init(objectId: ""))],
            ops: []
        )
        // WHEN
        context.setMapKey(path: [], key: "now", value: .date(now))

        //Then
        XCTAssertEqual(context.ops, [
            Op(action: .set, obj: .root, key: "now", value: .number(now.timeIntervalSince1970), datatype: .timestamp)
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            props: [
                "now": [
                    actor.actorId: .value(.init(value: .number(now.timeIntervalSince1970), datatype: .timestamp))
                ]
            ]
        )
        )
    }

    // should allow assignment of nestedDateValue
    func testContextSetMapKey11_1() {
        //Given
        let now = Date(timeIntervalSince1970: 0)
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [.root: .map(.init(objectId: ""))],
            ops: []
        )
        // WHEN
        context.setMapKey(path: [], key: "now", value: .map(Map(objectId: "", mapValues: ["now": .date(now)])))

        //Then
        XCTAssertEqual(context.ops, [
            Op(action: .makeMap, obj: .root, key: "now", child: context.ops[0].child),
            Op(action: .set, obj: context.ops[0].child!, key: "now", value: .number(now.timeIntervalSince1970), datatype: .timestamp)
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
    }

    // should allow assignment of Counter values
    func testContextSetMapKey12() {
        //Given
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [.root: .map(.init(objectId: ""))],
            ops: []
        )
        // WHEN
        context.setMapKey(path: [], key: "counter", value: .counter(3))

        //Then
        XCTAssertEqual(context.ops, [
                        Op(action: .set, obj: .root, key: "counter", value: 3.0, datatype: .counter)
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            props: [
                "counter": [
                    actor.actorId: .value(.init(value: 3.0, datatype: .counter))
                ]
            ]
        )
        )
    }

    // should allow assignment of UUID values
    func testContextSetMapKey13() {
        //Given
        let uuid = UUID().uuidString
        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [.root: .map(.init(objectId: ""))],
            ops: []
        )
        // WHEN
        context.setMapKey(path: [], key: "uuid", value: .primitive(.string(uuid)))

        //Then
        XCTAssertEqual(context.ops, [
            Op(action: .set, obj: .root, key: "uuid", value: .string(uuid))
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            props: [
                "uuid": [
                    actor.actorId: .value(.init(value: .string(uuid)))
                ]
            ]
        )
        )
    }


    // should overwrite an existing list element
    func testListManupulation1() {
        // Given
        let listId = ObjectId()
        let list: Object = .list(List(
                                    objectId: listId,
                                    listValues: ["swallow", "magpie"],
                                    conflicts: [["actor1": "swallow", "actor2": "swallow"]])
        )

        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [
                listId: list,
                .root: .map(Map(
                                objectId: .root,
                                mapValues: ["birds": list],
                                conflicts: ["birds": ["actor1": list]]))
            ]
        )

        // When
        context.setListIndex(path: [.init(key: "birds", objectId: listId)], index: 0, value: "starling")

        // Then
        XCTAssertEqual(context.ops, [
            Op(action: .set, obj: listId, key: .index(0), value: .string("starling"))
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            props: [
                "birds": [
                    "actor1": .object(.init(objectId: listId,
                                            type: .list,
                                            props: [
                                                0: [actor.actorId: "starling"]
                                            ]))
                ]
            ]
        )
        )
    }

    // should create nested objects on assignment
    func testListManupulation2() {
        // Given
        let listId = ObjectId()
        let list: Object = .list(
            List(
                objectId: listId,
                listValues: ["swallow", "magpie"],
                conflicts: [["actor1": "swallow", "actor2": "swallow"]]
            )
        )

        let actor = Actor()
        let context = Context(
            actorId: actor,
            applyPatch: applyPatch.observerDiff,
            updated: [:],
            cache: [
                listId: list,
                .root: .map(Map(
                                objectId: .root,
                                mapValues: ["birds": list],
                                conflicts: ["birds": ["actor1": list]]))
            ]
        )

        // When
        context.setListIndex(path: [.init(key: "birds", objectId: listId)], index: 1, value: .map(Map(objectId: "", mapValues: ["english": "goldfinch", "latin": "carduelis"])))

        // Then
        let nestedId = applyPatch.value!.props!["birds"]!["actor1"]!.props![1]![actor.actorId]!.objectId!
        XCTAssertEqual(context.ops, [
            Op(action: .makeMap, obj: listId, key: .index(1), child: nestedId),
            Op(action: .set, obj: nestedId, key: "english", value: .string("goldfinch")),
            Op(action: .set, obj: nestedId, key: "latin", value: .string("carduelis"))
        ])
        XCTAssertEqual(applyPatch.callCount, 1)
        XCTAssertEqual(applyPatch.value, ObjectDiff(
            objectId: .root,
            type: .map,
            props: [
                "birds": [
                    "actor1": .object(.init(objectId: listId,
                                            type: .list,
                                            props: [
                                                1: [actor.actorId: .object(.init(objectId: nestedId, type: .map, props: [
                                                    "english": [actor.actorId: "goldfinch"],
                                                    "latin": [actor.actorId: "carduelis"]
                                                ]))]
                                            ]))
                ]
            ]
        )
        )
    }

        // should create nested objects on insertion
        func testListManupulation3() {
            // Given
            let listId = ObjectId()
            let list: Object = .list(
                List(
                    objectId: listId,
                    listValues: ["swallow", "magpie"],
                    conflicts: [["actor1": "swallow", "actor2": "swallow"]]
                )
            )

            let actor = Actor()
            let context = Context(
                actorId: actor,
                applyPatch: applyPatch.observerDiff,
                updated: [:],
                cache: [
                    listId: list,
                    .root: .map(Map(
                                    objectId: .root,
                                    mapValues: ["birds": list],
                                    conflicts: ["birds": ["actor1": list]]))
                ]
            )

            // When
            context.splice(path: [.init(key: "birds", objectId: listId)], start: 2, deletions: 0, insertions: [.map(Map(objectId: "", mapValues: ["english": "goldfinch", "latin": "carduelis"]))])

            // Then
            let nestedId = applyPatch.value!.props!["birds"]!["actor1"]!.props![2]![actor.actorId]!.objectId!
            XCTAssertEqual(context.ops, [
                Op(action: .makeMap, obj: listId, key: 2, insert: true, child: nestedId),
                Op(action: .set, obj: nestedId, key: "english", value: .string("goldfinch")),
                Op(action: .set, obj: nestedId, key: "latin", value: .string("carduelis"))
            ])

            XCTAssertEqual(applyPatch.callCount, 1)
            XCTAssertEqual(applyPatch.value, ObjectDiff(
                objectId: .root,
                type: .map,
                props: [
                    "birds": [
                        "actor1": .object(.init(objectId: listId,
                                                type: .list,
                                                edits: [Edit(action: .insert, index: 2)],
                                                props: [
                                                    2: [actor.actorId: .object(.init(objectId: nestedId, type: .map, props: [
                                                        "english": [actor.actorId: "goldfinch"],
                                                        "latin": [actor.actorId: "carduelis"]
                                                    ]))]
                        ]))
                    ]
                ]
                )
            )
        }

        // should support deleting list elements
        func testListManupulation4() {
            // Given
            let listId = ObjectId()
            let list: Object = .list(
                List(
                    objectId: listId,
                    listValues: ["swallow", "magpie"],
                    conflicts: [["actor1": "swallow", "actor2": "swallow"]]
                )
            )

            let actor = Actor()
            let context = Context(
                actorId: actor,
                applyPatch: applyPatch.observerDiff,
                updated: [:],
                cache: [
                    listId: list,
                    .root: .map(Map(
                                    objectId: .root,
                                    mapValues: ["birds": list],
                                    conflicts: ["birds": ["actor1": list]]))
                ]
            )

            // When
            context.splice(path: [.init(key: "birds", objectId: listId)], start: 0, deletions: 2, insertions: [])

            // Then
            XCTAssertEqual(context.ops, [
                Op(action: .del, obj: listId, key: 0),
                Op(action: .del, obj: listId, key: 0)
            ])

            XCTAssertEqual(applyPatch.callCount, 1)
            XCTAssertEqual(applyPatch.value, ObjectDiff(
                objectId: .root,
                type: .map,
                props: [
                    "birds": [
                        "actor1": .object(
                            .init(objectId: listId,
                                  type: .list,
                                  edits: [
                                    Edit(action: .remove, index: 0),
                                    Edit(action: .remove, index: 0)
                                ],
                                  props: [:]
                            ))
                    ]
                ]
                )
            )
        }

        // should support deleting list elements
        func testListManupulation5() {
            // Given
            let listId = ObjectId()
            let list: Object = .list(
                List(
                    objectId: listId,
                    listValues: ["swallow", "magpie"],
                    conflicts: [["actor1": "swallow", "actor2": "swallow"]]
                )
            )

            let actor = Actor()
            let context = Context(
                actorId: actor,
                applyPatch: applyPatch.observerDiff,
                updated: [:],
                cache: [
                    listId: list,
                    .root: .map(Map(
                                    objectId: .root,
                                    mapValues: ["birds": list],
                                    conflicts: ["birds": ["actor1": list]]))
                ]
            )

            // When
            context.splice(path: [.init(key: "birds", objectId: listId)], start: 0, deletions: 2, insertions: [])

            // Then
            XCTAssertEqual(context.ops, [
                Op(action: .del, obj: listId, key: 0),
                Op(action: .del, obj: listId, key: 0)
            ])

            XCTAssertEqual(applyPatch.callCount, 1)
            XCTAssertEqual(applyPatch.value, ObjectDiff(
                objectId: .root,
                type: .map,
                props: [
                    "birds": [
                        "actor1": .object(
                            .init(objectId: listId,
                                  type: .list,
                                  edits: [
                                    Edit(action: .remove, index: 0),
                                    Edit(action: .remove, index: 0)
                                ],
                                  props: [:]
                            ))
                    ]
                ]
                )
            )
        }

        // should support list splicing
        func testListManupulation6() {
            // Given
            let listId = ObjectId()
            let list: Object = .list(
                List(
                    objectId: listId,
                    listValues: ["swallow", "magpie"],
                    conflicts: [["actor1": "swallow", "actor2": "swallow"]]
                )
            )

            let actor = Actor()
            let context = Context(
                actorId: actor,
                applyPatch: applyPatch.observerDiff,
                updated: [:],
                cache: [
                    listId: list,
                    .root: .map(Map(
                                    objectId: .root,
                                    mapValues: ["birds": list],
                                    conflicts: ["birds": ["actor1": list]]))
                ]
            )

            // When
            context.splice(path: [.init(key: "birds", objectId: listId)], start: 0, deletions: 1, insertions: ["starling", "goldfinch"])

            // Then
            XCTAssertEqual(context.ops, [
                Op(action: .del, obj: listId, key: 0),
                Op(action: .set, obj: listId, key: 0, insert: true, value: "starling"),
                Op(action: .set, obj: listId, key: 1, insert: true, value: "goldfinch"),
            ])

            XCTAssertEqual(applyPatch.callCount, 1)
            XCTAssertEqual(applyPatch.value, ObjectDiff(
                objectId: .root,
                type: .map,
                props: [
                    "birds": [
                        "actor1": .object(
                            .init(objectId: listId,
                                  type: .list,
                                  edits: [
                                    Edit(action: .remove, index: 0),
                                    Edit(action: .insert, index: 0),
                                    Edit(action: .insert, index: 1)
                                ],
                                  props: [
                                    0: [actor.actorId: "starling"],
                                    1: [actor.actorId: "goldfinch"]
                            ]))
                    ]
                ]
            ))

        }

        func testTableManipulation1() {
            let tableId = ObjectId()
            let table: Object = .table(Table(tableValues: [:], objectId: tableId))
            let actor = Actor()
            let context = Context(
                actorId: actor,
                applyPatch: applyPatch.observerDiff,
                updated: [:],
                cache: [
                    tableId: table,
                    .root: .map(Map(
                                    objectId: .root,
                                    mapValues: ["books": table],
                                    conflicts: ["books": ["actor1": table]])
                    )
                ]
            )

            //When
            let rowId = context.addTableRow(
                path: [.init(key: "books", objectId: tableId)],
                row: .map(Map(objectId: "", mapValues: ["author": "Mary Shelley", "title": "Frankenstein"], conflicts: [:]))
            )

            // Then
            XCTAssertEqual(context.ops, [
                Op(action: .makeMap, obj: tableId, key: .string(rowId.objectId), child: rowId),
                Op(action: .set, obj: rowId, key: "author", value: .string("Mary Shelley")),
                Op(action: .set, obj: rowId, key: "title", value: .string("Frankenstein"))
            ])

            XCTAssertEqual(applyPatch.callCount, 1)
            XCTAssertEqual(applyPatch.value, ObjectDiff(
                objectId: .root,
                type: .map,
                props: [
                    "books": [
                        "actor1": .object(
                            .init(objectId: tableId,
                                  type: .table,
                                  props: [
                                    .string(rowId.objectId): [
                                        rowId.objectId: .object(.init(
                                            objectId: rowId,
                                            type: .map,
                                            props: [
                                                "author": [actor.actorId: "Mary Shelley"],
                                                "title": [actor.actorId: "Frankenstein"]
                                        ]))
                                    ]
                            ]))
                    ]
                ]
            ))
        }

        // should delete a table row
        func testTableManipulation2() {
            let rowId = ObjectId()
            let row: Object = .map(Map(
                objectId: rowId,
                mapValues: [
                    "author": "Mary Shelley",
                    "title": "Frankenstein"],
                conflicts: [:]
            ))
            let tableId = ObjectId()
            let table: Object = .table(Table(tableValues: [rowId: row], objectId: tableId))
            let actor = Actor()
            let context = Context(
                actorId: actor,
                applyPatch: applyPatch.observerDiff,
                updated: [:],
                cache: [
                    tableId: table,
                    .root: .map(Map(
                                    objectId: .root,
                                    mapValues: ["books": table],
                                    conflicts: ["books": ["actor1": table]])
                    )
                ]
            )

            //When
            context.deleteTableRow(path: [.init(key: "books", objectId: tableId)], rowId: rowId)

            // Then
            XCTAssertEqual(context.ops, [
                Op(action: .del, obj: tableId, key: .string(rowId.objectId))
            ])

            XCTAssertEqual(applyPatch.callCount, 1)
            XCTAssertEqual(applyPatch.value, ObjectDiff(
                objectId: .root,
                type: .map,
                props: [
                    "books": [
                        "actor1": .object(
                            .init(objectId: tableId,
                                  type: .table,
                                  props: [
                                    .string(rowId.objectId): [:]
                            ]))
                    ]
                ]
            ))
        }

        //should increment a counter
        func testCounter1() {
            let counter: Object = .counter(0)
            let actor = Actor()
            let context = Context(
                actorId: actor,
                applyPatch: applyPatch.observerDiff,
                updated: [:],
                cache: [
                    .root: .map(Map(
                                    objectId: .root,
                                    mapValues: ["counter": counter],
                                    conflicts: ["counter": ["actor1": counter]])
                    )
                ]
            )

            //When
            context.increment(path: [], key: "counter", delta: 1)

            //Then
            XCTAssertEqual(context.ops, [
                Op(action: .inc, obj: .root, key: .string("counter"), value: 1.0)
            ])

            XCTAssertEqual(applyPatch.callCount, 1)
            XCTAssertEqual(applyPatch.value, ObjectDiff(
                objectId: .root,
                type: .map,
                props: [
                    "counter": [
                        actor.actorId: .value(.init(value: 1.0, datatype: .counter))
                    ]
                ]
            ))
        }

}
