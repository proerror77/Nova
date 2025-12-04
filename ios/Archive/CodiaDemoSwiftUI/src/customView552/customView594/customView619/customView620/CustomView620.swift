//
//  CustomView620.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView620: View {
    @State public var image430Path: String = "image430_42042"
    @State public var text294Text: String = "4"
    @State public var text295Text: String = "Lucy Liu"
    @State public var text296Text: String = "Morgan Stanley"
    @State public var text297Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView621(
                image430Path: image430Path,
                text294Text: text294Text,
                text295Text: text295Text,
                text296Text: text296Text,
                text297Text: text297Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView620_Previews: PreviewProvider {
    static var previews: some View {
        CustomView620()
    }
}
