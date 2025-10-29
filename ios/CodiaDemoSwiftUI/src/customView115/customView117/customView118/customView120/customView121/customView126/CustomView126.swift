//
//  CustomView126.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView126: View {
    @State public var image99Path: String = "image99_4554"
    @State public var text78Text: String = "Get the number of likes"
    @State public var text79Text: String = "61"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView127(
                image99Path: image99Path,
                text78Text: text78Text)
            Text(text79Text)
                .foregroundColor(Color(red: 0.44, green: 0.44, blue: 0.44, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView126_Previews: PreviewProvider {
    static var previews: some View {
        CustomView126()
    }
}
