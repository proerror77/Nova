//
//  CustomView343.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView343: View {
    @State public var image224Path: String = "image224_41068"
    @State public var text191Text: String = "Search"
    @State public var image225Path: String = "image225_41070"
    var body: some View {
        HStack(alignment: .center, spacing: 235) {
            CustomView344(
                image224Path: image224Path,
                text191Text: text191Text)
            Image(image225Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14, alignment: .topLeading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView343_Previews: PreviewProvider {
    static var previews: some View {
        CustomView343()
    }
}
