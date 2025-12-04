//
//  CustomView127.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView127: View {
    @State public var image99Path: String = "image99_4554"
    @State public var text78Text: String = "Get the number of likes"
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(image99Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36, alignment: .topLeading)
            Text(text78Text)
                .foregroundColor(Color(red: 0.66, green: 0.66, blue: 0.66, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView127_Previews: PreviewProvider {
    static var previews: some View {
        CustomView127()
    }
}
