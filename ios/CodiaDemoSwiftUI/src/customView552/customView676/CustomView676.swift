//
//  CustomView676.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView676: View {
    @State public var image472Path: String = "image472_42184"
    @State public var text322Text: String = "1"
    @State public var text323Text: String = "Lucy Liu"
    @State public var text324Text: String = "Morgan Stanley"
    @State public var text325Text: String = "2293"
    @State public var image478Path: String = "image478_42204"
    @State public var text326Text: String = "2"
    @State public var text327Text: String = "Lucy Liu"
    @State public var text328Text: String = "Morgan Stanley"
    @State public var text329Text: String = "2293"
    @State public var image484Path: String = "image484_42224"
    @State public var text330Text: String = "3"
    @State public var text331Text: String = "Lucy Liu"
    @State public var text332Text: String = "Morgan Stanley"
    @State public var text333Text: String = "2293"
    @State public var image490Path: String = "image490_42244"
    @State public var text334Text: String = "4"
    @State public var text335Text: String = "Lucy Liu"
    @State public var text336Text: String = "Morgan Stanley"
    @State public var text337Text: String = "2293"
    @State public var image496Path: String = "image496_42264"
    @State public var text338Text: String = "5"
    @State public var text339Text: String = "Lucy Liu"
    @State public var text340Text: String = "Morgan Stanley"
    @State public var text341Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView677(
                image472Path: image472Path,
                text322Text: text322Text,
                text323Text: text323Text,
                text324Text: text324Text,
                text325Text: text325Text)
                .frame(width: 309, height: 389)
                .offset(x: -931)
            CustomView685(
                image478Path: image478Path,
                text326Text: text326Text,
                text327Text: text327Text,
                text328Text: text328Text,
                text329Text: text329Text)
                .frame(width: 311, height: 392)
                .offset(x: -612)
            CustomView693(
                image484Path: image484Path,
                text330Text: text330Text,
                text331Text: text331Text,
                text332Text: text332Text,
                text333Text: text333Text)
                .frame(width: 312, height: 392)
                .offset(x: -291)
            CustomView701(
                image490Path: image490Path,
                text334Text: text334Text,
                text335Text: text335Text,
                text336Text: text336Text,
                text337Text: text337Text)
                .frame(width: 311, height: 392)
                .offset(x: 41)
            CustomView709(
                image496Path: image496Path,
                text338Text: text338Text,
                text339Text: text339Text,
                text340Text: text340Text,
                text341Text: text341Text)
                .frame(width: 311, height: 392)
                .offset(x: 372)
        }
        .frame(width: 393, height: 392, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView676_Previews: PreviewProvider {
    static var previews: some View {
        CustomView676()
    }
}
