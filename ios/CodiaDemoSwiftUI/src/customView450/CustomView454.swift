//
//  CustomView454.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView454: View {
    @State public var image280Path: String = "image280_41412"
    @State public var text229Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView455(
                image280Path: image280Path,
                text229Text: text229Text)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(width: 310, height: 32, alignment: .topLeading)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 37))
    }
}

struct CustomView454_Previews: PreviewProvider {
    static var previews: some View {
        CustomView454()
    }
}
