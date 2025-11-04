//
//  CustomView122.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView122: View {
    @State public var image97Path: String = "image97_4540"
    @State public var text74Text: String = "Number of posts"
    @State public var text75Text: String = "30"
    var body: some View {
        HStack(alignment: .center, spacing: 48) {
            CustomView123(
                image97Path: image97Path,
                text74Text: text74Text)
            Text(text75Text)
                .foregroundColor(Color(red: 0.44, green: 0.44, blue: 0.44, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView122_Previews: PreviewProvider {
    static var previews: some View {
        CustomView122()
    }
}
