//
//  CustomView124.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView124: View {
    @State public var image98Path: String = "image98_4547"
    @State public var text76Text: String = "Gain collection points"
    @State public var text77Text: String = "479"
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            CustomView125(
                image98Path: image98Path,
                text76Text: text76Text)
            Text(text77Text)
                .foregroundColor(Color(red: 0.44, green: 0.44, blue: 0.44, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView124_Previews: PreviewProvider {
    static var previews: some View {
        CustomView124()
    }
}
