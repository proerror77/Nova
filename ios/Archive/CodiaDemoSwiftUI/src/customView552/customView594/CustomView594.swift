//
//  CustomView594.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView594: View {
    @State public var image412Path: String = "image412_41982"
    @State public var text282Text: String = "1"
    @State public var text283Text: String = "Lucy Liu"
    @State public var text284Text: String = "Morgan Stanley"
    @State public var text285Text: String = "2293"
    @State public var image418Path: String = "image418_42002"
    @State public var text286Text: String = "2"
    @State public var text287Text: String = "Lucy Liu"
    @State public var text288Text: String = "Morgan Stanley"
    @State public var text289Text: String = "2293"
    @State public var image424Path: String = "image424_42022"
    @State public var text290Text: String = "3"
    @State public var text291Text: String = "Lucy Liu"
    @State public var text292Text: String = "Morgan Stanley"
    @State public var text293Text: String = "2293"
    @State public var image430Path: String = "image430_42042"
    @State public var text294Text: String = "4"
    @State public var text295Text: String = "Lucy Liu"
    @State public var text296Text: String = "Morgan Stanley"
    @State public var text297Text: String = "2293"
    @State public var image436Path: String = "image436_42062"
    @State public var text298Text: String = "5"
    @State public var text299Text: String = "Lucy Liu"
    @State public var text300Text: String = "Morgan Stanley"
    @State public var text301Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView595(
                image412Path: image412Path,
                text282Text: text282Text,
                text283Text: text283Text,
                text284Text: text284Text,
                text285Text: text285Text)
                .frame(width: 309, height: 389)
                .offset(x: -288)
            CustomView603(
                image418Path: image418Path,
                text286Text: text286Text,
                text287Text: text287Text,
                text288Text: text288Text,
                text289Text: text289Text)
                .frame(width: 311, height: 392)
                .offset(x: 41)
            CustomView611(
                image424Path: image424Path,
                text290Text: text290Text,
                text291Text: text291Text,
                text292Text: text292Text,
                text293Text: text293Text)
                .frame(width: 312, height: 392)
                .offset(x: 372)
            CustomView619(
                image430Path: image430Path,
                text294Text: text294Text,
                text295Text: text295Text,
                text296Text: text296Text,
                text297Text: text297Text)
                .frame(width: 311, height: 392)
                .offset(x: 694)
            CustomView627(
                image436Path: image436Path,
                text298Text: text298Text,
                text299Text: text299Text,
                text300Text: text300Text,
                text301Text: text301Text)
                .frame(width: 311, height: 392)
                .offset(x: 1015)
        }
        .frame(width: 393, height: 392, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView594_Previews: PreviewProvider {
    static var previews: some View {
        CustomView594()
    }
}
