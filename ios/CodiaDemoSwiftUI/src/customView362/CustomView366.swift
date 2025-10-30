//
//  CustomView366.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView366: View {
    @State public var image238Path: String = "image238_41234"
    @State public var text200Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView367(
                image238Path: image238Path,
                text200Text: text200Text)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(width: 349, height: 32, alignment: .topLeading)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }
}

struct CustomView366_Previews: PreviewProvider {
    static var previews: some View {
        CustomView366()
    }
}
