//
//  CustomView685.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView685: View {
    @State public var image478Path: String = "image478_42204"
    @State public var text326Text: String = "2"
    @State public var text327Text: String = "Lucy Liu"
    @State public var text328Text: String = "Morgan Stanley"
    @State public var text329Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView686(
                image478Path: image478Path,
                text326Text: text326Text,
                text327Text: text327Text,
                text328Text: text328Text,
                text329Text: text329Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView685_Previews: PreviewProvider {
    static var previews: some View {
        CustomView685()
    }
}
